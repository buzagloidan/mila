import AVFoundation
import Observation
import UIKit

@MainActor @Observable
final class RecordingSession {
    enum Phase { case idle, preparing, recording, importing, finishing }
    private(set) var phase = Phase.idle
    private(set) var current: Transcript?
    private(set) var progress = 0.0
    var errorMessage: String?
    private let store: TranscriptStore
    private let worker = TranscriptionWorker()
    private let liveActivity = RecordingLiveActivity()
    private var engine: AVAudioEngine?
    @ObservationIgnored private let notifications = NotificationTokens()
    private var checkpoint = Date.distantPast
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var importCancelled = false
    var isBusy: Bool { phase != .idle }

    func clearPresentation() {
        guard !isBusy else { return }
        current = nil
        errorMessage = nil
    }

    init(store: TranscriptStore) {
        self.store = store
        notifications.tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.errorMessage = "ההקלטה הופסקה בעקבות הפרעה במכשיר. התמלול עד לנקודה זו נשמר."
                await self.stop()
            }
        })
        notifications.tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.errorMessage = "מקור השמע נותק. ההקלטה נעצרה והתמלול נשמר."
                await self.stop()
            }
        })
        notifications.tokens.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.errorMessage = "הגדרות השמע השתנו. ההקלטה נעצרה והתמלול נשמר."
                await self.stop()
            }
        })
    }

    func start(title: String, keepAudio: Bool) async {
        guard !isBusy else { return }
        phase = .preparing
        errorMessage = nil
        current = nil
        let permitted = await AVAudioApplication.requestRecordPermission()
        guard permitted else { errorMessage = VoiceError.microphoneDenied.localizedDescription; phase = .idle; return }
        var draft = Transcript(title: title.isEmpty ? "הקלטה חדשה" : title)
        if keepAudio { draft.audioFilename = "\(draft.id).m4a" }
        current = draft
        checkpoint = .distantPast
        do {
            try store.save(draft)
            try await AudioSessionController.shared.activate(for: .recording)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.invalidAudio }
            let id = draft.id
            try await worker.prepare(audioURL: store.audioURL(for: draft), sampleRate: format.sampleRate, update: { [weak self] snapshot in
                Task { @MainActor in self?.receive(snapshot, id: id) }
            }, failure: { [weak self] error in
                Task { @MainActor in
                    guard let self, self.current?.id == id else { return }
                    self.errorMessage = error.localizedDescription
                    await self.stop()
                }
            })
            let worker = self.worker
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                if let samples = try? TranscriptionWorker.monoSamples(buffer) { worker.enqueue(samples: samples, sampleRate: format.sampleRate) }
            }
            self.engine = engine
            engine.prepare()
            try engine.start()
            phase = .recording
            liveActivity.start(sessionID: draft.id, startedAt: Date())
        } catch {
            errorMessage = error.localizedDescription
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            engine = nil
            _ = try? await worker.finish()
            try? await AudioSessionController.shared.deactivate()
            phase = .idle
        }
    }

    func stop() async {
        guard phase == .recording else { return }
        phase = .finishing
        beginBackgroundTask()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        defer {
            phase = .idle
            endBackgroundTask()
        }
        var saved = false
        do {
            let snapshot = try await worker.finish()
            try commit(snapshot, complete: true)
            saved = true
        } catch { errorMessage = "לא ניתן לשמור את התמלול: \(error.localizedDescription)" }
        try? await AudioSessionController.shared.deactivate()
        await liveActivity.end(saved: saved)
    }

    @discardableResult
    func importAudio(_ url: URL, keepAudio: Bool, title: String? = nil, sourceID: UUID? = nil) async -> Transcript? {
        guard !isBusy else { return nil }
        phase = .preparing
        errorMessage = nil
        progress = 0
        importCancelled = false
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() }; phase = .idle; endBackgroundTask() }
        var draft = Transcript(title: title ?? url.deletingPathExtension().lastPathComponent)
        draft.sourceID = sourceID
        if keepAudio { draft.audioFilename = "\(draft.id).\(url.pathExtension.isEmpty ? "audio" : url.pathExtension)" }
        current = draft
        checkpoint = .distantPast
        do {
            try store.save(draft)
            phase = .importing
            beginBackgroundTask()
            let id = draft.id
            let worker = self.worker
            let result = try await withTaskCancellationHandler {
                try await worker.importFile(url, copyTo: store.audioURL(for: draft)) { [weak self] snapshot in
                    Task { @MainActor in self?.receive(snapshot, id: id) }
                }
            } onCancel: { worker.cancelImport() }
            let complete = !importCancelled && !Task.isCancelled && (result.progress ?? 0) >= 1
            try commit(result, complete: complete)
            if !complete { errorMessage = VoiceError.cancelled.localizedDescription }
            return current
        } catch {
            errorMessage = "לא ניתן לתמלל את הקובץ: \(error.localizedDescription)"
            // Keep the last persisted checkpoint and any retained audio available for recovery.
            return nil
        }
    }

    func cancelImport() {
        guard phase == .importing else { return }
        importCancelled = true
        phase = .finishing
        worker.cancelImport()
    }

    private func receive(_ snapshot: RecognitionSnapshot, id: UUID) {
        // Finalization commits the authoritative result; queued live updates must not replace it.
        guard current?.id == id, phase == .recording || phase == .importing else { return }
        current?.text = snapshot.text
        current?.duration = snapshot.duration
        progress = snapshot.progress ?? 0
        if Date().timeIntervalSince(checkpoint) >= 5, let current {
            do { try store.save(current); checkpoint = Date() }
            catch { errorMessage = "שמירת התמלול נכשלה: \(error.localizedDescription)" }
        }
    }

    private func commit(_ snapshot: RecognitionSnapshot, complete: Bool) throws {
        guard var transcript = current else { return }
        transcript.text = snapshot.text
        transcript.duration = snapshot.duration
        transcript.isComplete = complete
        current = transcript
        try store.save(transcript)
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "שמירת תמלול") { [weak self] in
            Task { @MainActor in self?.cancelImport(); self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

}

private final class NotificationTokens {
    var tokens: [NSObjectProtocol] = []
    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}

/// Serializes hardware session changes away from the main thread on every supported iOS version.
/// Keep this shared by recording and playback so a pending deactivation cannot overtake a new activation.
final class AudioSessionController: @unchecked Sendable {
    enum Purpose { case recording, playback }
    static let shared = AudioSessionController()

    private let queue = DispatchQueue(label: "hebrewvoice.audio-session", qos: .userInitiated)
    private let configure: (Purpose) throws -> Void
    private let setActive: (Bool) throws -> Void

    init(configure: @escaping (Purpose) throws -> Void = { purpose in
        let session = AVAudioSession.sharedInstance()
        switch purpose {
        case .recording: try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        case .playback: try session.setCategory(.playback, mode: .spokenAudio)
        }
    }, setActive: @escaping (Bool) throws -> Void = { active in
        try AVAudioSession.sharedInstance().setActive(active, options: active ? [] : .notifyOthersOnDeactivation)
    }) {
        self.configure = configure
        self.setActive = setActive
    }

    func activate(for purpose: Purpose) async throws {
        try await perform {
            try self.configure(purpose)
            try self.setActive(true)
        }
    }

    func deactivate() async throws {
        try await perform { try self.setActive(false) }
    }

    /// Enqueue immediately for synchronous view teardown, preserving order with subsequent activations.
    func deactivateInBackground() {
        queue.async { try? self.setActive(false) }
    }

    private func perform(_ operation: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { continuation.resume(with: Result { try operation() }) }
        }
    }
}
