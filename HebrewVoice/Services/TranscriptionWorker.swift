import AVFoundation
import Foundation

struct RecognitionSnapshot: Sendable {
    let text: String
    let duration: TimeInterval
    var progress: Double? = nil
}

/// The native engine, file reads and disk writes share one queue. No inference runs on the UI/audio thread.
final class TranscriptionWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "hebrewvoice.inference", qos: .userInitiated)
    private let lock = NSLock()
    private var cancelled = false
    private var pendingSeconds = 0.0
    private var accepting = false
    // Queue-confined properties:
    private var recognizer: NativeRecognizer?
    private var audioFile: AVAudioFile?
    private var update: ((RecognitionSnapshot) -> Void)?
    private var failure: ((Error) -> Void)?
    private var lastUpdate = Date.distantPast

    func prepare(audioURL: URL?, sampleRate: Double, update: @escaping (RecognitionSnapshot) -> Void,
                 failure: @escaping (Error) -> Void) async throws {
        lock.withLock { cancelled = false; pendingSeconds = 0; accepting = false }
        try await perform {
            guard let root = Bundle.main.url(forResource: "Model", withExtension: nil) else { throw VoiceError.modelMissing }
            self.recognizer = try NativeRecognizer(modelDirectory: root)
            try self.recognizer?.begin()
            self.update = update
            self.failure = failure
            self.lastUpdate = .distantPast
            if let audioURL {
                guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { throw VoiceError.invalidAudio }
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: Int(min(64_000, sampleRate * 2))
                ]
                self.audioFile = try AVAudioFile(forWriting: audioURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: audioURL.path)
            }
            self.lock.withLock { self.accepting = true }
        }
    }

    func enqueue(samples: [Float], sampleRate: Double) {
        let seconds = Double(samples.count) / sampleRate
        let action: Int = lock.withLock {
            guard accepting else { return 0 }
            guard pendingSeconds + seconds <= 20 else { accepting = false; return 2 }
            pendingSeconds += seconds
            return 1
        }
        if action == 2 {
            queue.async { self.failure?(VoiceError.overloaded) }
            return
        }
        guard action == 1 else { return }
        queue.async {
            defer { self.lock.withLock { self.pendingSeconds -= seconds } }
            do {
                if let audioFile = self.audioFile {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                          let channel = buffer.floatChannelData?[0] else { throw VoiceError.invalidAudio }
                    buffer.frameLength = buffer.frameCapacity
                    samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
                    try audioFile.write(from: buffer)
                }
                self.recognizer?.accept(samples, sampleRate: Int32(sampleRate))
                self.publish()
            } catch {
                let firstFailure = self.lock.withLock { let wasAccepting = self.accepting; self.accepting = false; return wasAccepting }
                if firstFailure { self.failure?(error) }
            }
        }
    }

    func finish() async throws -> RecognitionSnapshot {
        lock.withLock { accepting = false }
        return try await perform {
            self.recognizer?.finish()
            let result = self.snapshot()
            self.audioFile = nil
            self.recognizer = nil
            self.update = nil
            self.failure = nil
            return result
        }
    }

    func cancelImport() { lock.withLock { cancelled = true } }

    func importFile(_ url: URL, copyTo destination: URL?, update: @escaping (RecognitionSnapshot) -> Void) async throws -> RecognitionSnapshot {
        lock.withLock { cancelled = false }
        try Task.checkCancellation()
        return try await perform {
            defer { self.audioFile = nil; self.recognizer = nil; self.update = nil }
            let input = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard input.length > 0, input.processingFormat.sampleRate > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 4096) else { throw VoiceError.invalidAudio }
            if let destination {
                try FileManager.default.copyItem(at: url, to: destination)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            }
            guard let root = Bundle.main.url(forResource: "Model", withExtension: nil) else { throw VoiceError.modelMissing }
            self.recognizer = try NativeRecognizer(modelDirectory: root)
            try self.recognizer?.begin()
            self.update = update
            self.lastUpdate = .distantPast
            while input.framePosition < input.length {
                if self.lock.withLock({ self.cancelled }) { break }
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                let samples = try Self.monoSamples(buffer)
                self.recognizer?.accept(samples, sampleRate: Int32(input.processingFormat.sampleRate))
                self.publish(progress: Double(input.framePosition) / Double(input.length))
            }
            self.recognizer?.finish()
            return self.snapshot(progress: Double(input.framePosition) / Double(input.length))
        }
    }

    static func monoSamples(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let channels = buffer.floatChannelData, buffer.format.channelCount > 0 else { throw VoiceError.invalidAudio }
        let count = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        if channelCount == 1 { return Array(UnsafeBufferPointer(start: channels[0], count: count)) }
        var mono = [Float](repeating: 0, count: count)
        for channel in 0..<channelCount {
            for index in 0..<count { mono[index] += channels[channel][index] / Float(channelCount) }
        }
        return mono
    }

    private func snapshot(progress: Double? = nil) -> RecognitionSnapshot {
        RecognitionSnapshot(text: recognizer?.text ?? "", duration: recognizer?.duration ?? 0, progress: progress)
    }

    private func publish(progress: Double? = nil) {
        guard Date().timeIntervalSince(lastUpdate) >= 0.25 else { return }
        lastUpdate = Date()
        update?(snapshot(progress: progress))
    }

    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }
}
