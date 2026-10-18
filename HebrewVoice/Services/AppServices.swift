import Foundation
import Observation

@MainActor @Observable
final class AppNavigation {
    enum Destination: Equatable { case recorder, transcript(UUID) }
    struct Request { let id = UUID(); let destination: Destination }
    private(set) var request: Request?
    func show(_ destination: Destination) { request = Request(destination: destination) }
    func consume(_ id: UUID) { if request?.id == id { request = nil } }
}

actor SharedInboxRepository {
    private let customRoot: URL?
    init(root: URL? = nil) { customRoot = root }
    func items() throws -> [SharedAudioItem] { try SharedAudioStorage(root: customRoot).items() }
    func audioURL(for item: SharedAudioItem) throws -> URL { try SharedAudioStorage(root: customRoot).audioURL(for: item) }
    func remove(_ item: SharedAudioItem) throws { try SharedAudioStorage(root: customRoot).remove(id: item.id) }
    func enqueue(_ url: URL) throws -> SharedAudioItem { try SharedAudioStorage(root: customRoot).enqueue(file: url) }
}

@MainActor @Observable
final class SharedInbox {
    private(set) var items: [SharedAudioItem] = []
    var errorMessage: String?
    private var revision = 0
    let repository: SharedInboxRepository
    init(repository: SharedInboxRepository = SharedInboxRepository()) { self.repository = repository }

    func refresh() async {
        revision += 1
        let request = revision
        do {
            let refreshed = try await repository.items()
            guard revision == request else { return }
            items = refreshed
            errorMessage = nil
        } catch { if revision == request { errorMessage = error.localizedDescription } }
    }

    func remove(_ item: SharedAudioItem) async throws {
        try await repository.remove(item)
        revision += 1
        items.removeAll { $0.id == item.id }
    }
}

/// A single app-process service graph serves scenes, App Intents and Live Activity actions.
@MainActor
final class AppServices {
    static let shared = AppServices()
    let store: TranscriptStore
    let session: RecordingSession
    let navigation = AppNavigation()
    let inbox: SharedInbox
    private var receivingURLs = Set<URL>()
    private var attemptedSources = Set<UUID>()
    private var isProcessingInbox = false
    private var inboxWorkRequested = false

    init(store: TranscriptStore? = nil, inbox: SharedInbox? = nil) {
        let store = store ?? TranscriptStore()
        self.store = store
        self.session = RecordingSession(store: store)
        self.inbox = inbox ?? SharedInbox()
    }

    var keepAudio: Bool { UserDefaults.standard.object(forKey: "keepAudio") as? Bool ?? true }

    /// iOS opens this app directly for an audio document. Stage the file before starting inference.
    func receiveAudioDocument(_ url: URL) async {
        guard url.isFileURL else { return }
        let key = url.standardizedFileURL
        guard receivingURLs.insert(key).inserted else { return }
        defer { receivingURLs.remove(key) }
        do {
            _ = try await inbox.repository.enqueue(url)
            // With open-in-place disabled, iOS may give us its own copy in Documents/Inbox.
            // Only that managed copy may be removed; never remove a user's source in Files.
            let importedFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Inbox", isDirectory: true).resolvingSymlinksInPath()
            if url.resolvingSymlinksInPath().deletingLastPathComponent() == importedFolder {
                try? FileManager.default.removeItem(at: url)
            }
            await processPendingAudio()
        } catch { inbox.errorMessage = error.localizedDescription }
    }

    /// Resumes queued/legacy shares without asking the user to confirm the same import again.
    func processPendingAudio() async {
        inboxWorkRequested = true
        guard !isProcessingInbox, !session.isBusy else { return }
        isProcessingInbox = true
        defer { isProcessingInbox = false }
        repeat {
            inboxWorkRequested = false
            await inbox.refresh()
            while !session.isBusy, let item = inbox.items.first(where: { !attemptedSources.contains($0.id) }) {
                attemptedSources.insert(item.id)
                do { try await transcribeShared(item) }
                catch { inbox.errorMessage = error.localizedDescription; return }
            }
        } while inboxWorkRequested && !session.isBusy
    }

    func startRecording() async throws {
        guard !session.isBusy else { throw IntegrationError.busy }
        navigation.show(.recorder)
        await session.start(title: "הקלטה חדשה", keepAudio: keepAudio)
        guard session.phase == .recording else { throw SessionActionError(message: session.errorMessage ?? VoiceError.engineFailed.localizedDescription) }
    }

    func openLatestTranscript() throws {
        guard !session.isBusy else { throw IntegrationError.busy }
        guard let transcript = store.transcripts.first else { throw IntegrationError.noTranscript }
        navigation.show(.transcript(transcript.id))
    }

    func transcribe(_ url: URL, title: String? = nil) async throws -> String {
        guard !session.isBusy else { throw IntegrationError.busy }
        navigation.show(.recorder)
        guard let transcript = await session.importAudio(url, keepAudio: keepAudio, title: title), transcript.isComplete else {
            throw SessionActionError(message: session.errorMessage ?? IntegrationError.interrupted.localizedDescription)
        }
        return transcript.text
    }

    func transcribeShared(_ item: SharedAudioItem) async throws {
        guard !session.isBusy else { throw IntegrationError.busy }
        if let existing = store.transcripts.first(where: { $0.sourceID == item.id && $0.isComplete }) {
            try await inbox.remove(item)
            navigation.show(.transcript(existing.id))
            return
        }
        let url = try await inbox.repository.audioURL(for: item)
        navigation.show(.recorder)
        guard let transcript = await session.importAudio(url, keepAudio: keepAudio, title: item.title, sourceID: item.id), transcript.isComplete else {
            throw SessionActionError(message: session.errorMessage ?? IntegrationError.interrupted.localizedDescription)
        }
        // Delete the pending source only after the final transcript is durably saved.
        try await inbox.remove(item)
    }

    func stopRecording(sessionID: UUID) async {
        if session.current?.id == sessionID && session.phase == .recording { await session.stop() }
        else { await RecordingLiveActivity.endStaleActivity(sessionID: sessionID) }
    }
}

struct SessionActionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
