import AVFoundation
import XCTest
@testable import HebrewVoice

final class HebrewVoiceTests: XCTestCase {
    @MainActor
    func testAudioSessionChangesRunOffMainThreadInOrder() async throws {
        let events = AudioSessionEvents()
        let controller = AudioSessionController(configure: { purpose in
            XCTAssertFalse(Thread.isMainThread)
            events.append(purpose == .recording ? "recording" : "playback")
        }, setActive: { active in
            XCTAssertFalse(Thread.isMainThread)
            events.append(active ? "activate" : "deactivate")
        })
        try await controller.activate(for: .recording)
        controller.deactivateInBackground()
        try await controller.activate(for: .playback)
        try await controller.deactivate()
        XCTAssertEqual(events.values, ["recording", "activate", "deactivate", "playback", "activate", "deactivate"])
    }

    @MainActor
    func testAudioSessionConfigurationFailureReachesCaller() async {
        enum Failure: Error { case unavailable }
        let controller = AudioSessionController(configure: { _ in throw Failure.unavailable }, setActive: { _ in
            XCTFail("Must not activate after category configuration fails")
        })
        do {
            try await controller.activate(for: .recording)
            XCTFail("Expected the audio session error to reach the UI caller")
        } catch {
            guard case Failure.unavailable = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testBundledModelRecognizesHebrewWithoutNetworkOrMicrophone() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        let worker = TranscriptionWorker()
        let result = try await worker.importFile(url, copyTo: nil) { _ in }
        XCTAssertTrue(result.text.contains("שלום"), "Actual recognition: \(result.text)")
        XCTAssertGreaterThan(result.duration, 1)
        XCTAssertEqual(result.progress, 1)
    }

    func testEndpointResetsPreserveMultipleUtterancesAndFinalChunk() throws {
        let directory = try XCTUnwrap(Bundle.main.url(forResource: "Model", withExtension: nil))
        let engine = try NativeRecognizer(modelDirectory: directory)
        try engine.begin()
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = try TranscriptionWorker.monoSamples(buffer)
        for _ in 0..<4 {
            for start in stride(from: 0, to: samples.count, by: 3200) {
                engine.accept(Array(samples[start..<min(samples.count, start + 3200)]), sampleRate: 16_000)
            }
            engine.accept([Float](repeating: 0, count: 48_000), sampleRate: 16_000)
        }
        let before = engine.duration
        engine.finish()
        XCTAssertEqual(engine.duration, before, "Flush padding must not extend the recorded duration")
        XCTAssertEqual(engine.text.components(separatedBy: "שלום").count - 1, 4, engine.text)
        try engine.begin()
        engine.accept([Float](repeating: 0, count: 32_000), sampleRate: 16_000)
        engine.finish()
        XCTAssertEqual(engine.text, "", "Starting another session must clear the previous transcript")
    }

    func testStereoAudioIsDownmixedToMono() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        buffer.frameLength = 3
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for index in 0..<3 { channels[0][index] = 0.8; channels[1][index] = -0.2 }
        let samples = try TranscriptionWorker.monoSamples(buffer)
        XCTAssertEqual(samples.count, 3)
        for sample in samples { XCTAssertEqual(sample, 0.3, accuracy: 0.0001) }
    }

    func testLivePipelineSavesAudioAndFlushesTranscript() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        let input = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 3200))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).m4a")
        defer { try? FileManager.default.removeItem(at: destination) }
        let worker = TranscriptionWorker()
        try await worker.prepare(audioURL: destination, sampleRate: 16_000, update: { _ in }, failure: { XCTFail($0.localizedDescription) })
        while input.framePosition < input.length {
            try input.read(into: buffer)
            worker.enqueue(samples: try TranscriptionWorker.monoSamples(buffer), sampleRate: 16_000)
        }
        let result = try await worker.finish()
        XCTAssertTrue(result.text.contains("שלום"), result.text)
        let saved = try AVAudioFile(forReading: destination)
        let savedDuration = Double(saved.length) / saved.processingFormat.sampleRate
        XCTAssertEqual(savedDuration, result.duration, accuracy: 0.15)
    }

    func testCancellingImportReturnsPartialResult() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        let worker = TranscriptionWorker()
        let result = try await worker.importFile(url, copyTo: nil) { _ in worker.cancelImport() }
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertLessThan(try XCTUnwrap(result.progress), 1)
    }

    func testMicrophoneBacklogIsBounded() async throws {
        let worker = TranscriptionWorker()
        let failed = expectation(description: "Overloaded audio queue stops accepting samples")
        try await worker.prepare(audioURL: nil, sampleRate: 16_000, update: { _ in }, failure: { error in
            guard case VoiceError.overloaded = error else { return XCTFail("Unexpected error: \(error)") }
            failed.fulfill()
        })
        worker.enqueue(samples: [Float](repeating: 0, count: 21 * 16_000), sampleRate: 16_000)
        let result = try await worker.finish()
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(result.duration, 0, "The rejected buffer must not enter inference")
    }

    @MainActor
    func testCheckpointSurvivesRestartAndDeletionRemovesAudio() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptStore(directory: directory)
        var draft = Transcript(title: "הרצאה בעברית")
        draft.text = "שלום, עולם. מספר 123 וגם Swift."
        draft.audioFilename = "\(draft.id).caf"
        draft.duration = 67
        try Data([1, 2, 3]).write(to: try XCTUnwrap(store.audioURL(for: draft)))
        try store.save(draft)
        let reloaded = TranscriptStore(directory: directory)
        XCTAssertEqual(reloaded.transcripts, [draft])
        XCTAssertFalse(try XCTUnwrap(reloaded.transcripts.first).isComplete)
        draft.isComplete = true
        try reloaded.save(draft)
        XCTAssertEqual(reloaded.transcripts.count, 1)
        XCTAssertTrue(reloaded.transcripts[0].isComplete)
        try reloaded.delete(draft)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}

private final class AudioSessionEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func append(_ value: String) { lock.withLock { events.append(value) } }
    var values: [String] { lock.withLock { events } }
}
