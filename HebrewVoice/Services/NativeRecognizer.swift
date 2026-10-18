import Foundation
import SherpaOnnxC

/// All methods and destruction must stay on the transcription worker's serial queue.
final class NativeRecognizer {
    private let recognizer: OpaquePointer
    private var stream: OpaquePointer?
    private var paragraphs: [String] = []
    private var sampleRate: Int32 = 16_000
    private(set) var duration: TimeInterval = 0

    init(modelDirectory: URL) throws {
        let files = ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]
        guard files.allSatisfy({ FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent($0).path) }) else {
            throw VoiceError.modelMissing
        }
        // The C constructor copies these strings before returning.
        let strings = (files.map { modelDirectory.appendingPathComponent($0).path } + ["cpu", "zipformer2", "greedy_search"])
            .map { strdup($0)! }
        defer { strings.forEach { free($0) } }
        var config = SherpaOnnxOnlineRecognizerConfig()
        config.feat_config.sample_rate = 16_000
        config.feat_config.feature_dim = 80
        config.model_config.transducer.encoder = UnsafePointer(strings[0])
        config.model_config.transducer.decoder = UnsafePointer(strings[1])
        config.model_config.transducer.joiner = UnsafePointer(strings[2])
        config.model_config.tokens = UnsafePointer(strings[3])
        config.model_config.provider = UnsafePointer(strings[4])
        config.model_config.model_type = UnsafePointer(strings[5])
        config.model_config.num_threads = 2
        config.decoding_method = UnsafePointer(strings[6])
        config.max_active_paths = 4
        config.enable_endpoint = 1
        config.rule1_min_trailing_silence = 2.4
        config.rule2_min_trailing_silence = 1.2
        config.rule3_min_utterance_length = 30
        guard let handle = SherpaOnnxCreateOnlineRecognizer(&config) else { throw VoiceError.engineFailed }
        recognizer = handle
    }

    func begin() throws {
        if let stream { SherpaOnnxDestroyOnlineStream(stream) }
        stream = SherpaOnnxCreateOnlineStream(recognizer)
        guard stream != nil else { throw VoiceError.engineFailed }
        paragraphs = []
        duration = 0
    }

    func accept(_ samples: [Float], sampleRate: Int32) {
        guard let stream, !samples.isEmpty else { return }
        self.sampleRate = sampleRate
        duration += Double(samples.count) / Double(sampleRate)
        samples.withUnsafeBufferPointer {
            SherpaOnnxOnlineStreamAcceptWaveform(stream, sampleRate, $0.baseAddress, Int32($0.count))
        }
        decode()
        if SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) != 0 {
            let final = currentText()
            if !final.isEmpty { paragraphs.append(final) }
            SherpaOnnxOnlineStreamReset(recognizer, stream)
        }
    }

    var text: String { (paragraphs + [currentText()]).filter { !$0.isEmpty }.joined(separator: "\n\n") }

    func finish() {
        guard let stream else { return }
        // Flush the model's final 1.28-second chunk without adding padding to the duration.
        let padding = [Float](repeating: 0, count: Int(Double(sampleRate) * 1.5))
        padding.withUnsafeBufferPointer {
            SherpaOnnxOnlineStreamAcceptWaveform(stream, sampleRate, $0.baseAddress, Int32($0.count))
        }
        SherpaOnnxOnlineStreamInputFinished(stream)
        decode()
        let final = currentText()
        if !final.isEmpty { paragraphs.append(final) }
        SherpaOnnxDestroyOnlineStream(stream)
        self.stream = nil
    }

    private func decode() {
        guard let stream else { return }
        while SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0 { SherpaOnnxDecodeOnlineStream(recognizer, stream) }
    }

    private func currentText() -> String {
        guard let stream, let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else { return "" }
        defer { SherpaOnnxDestroyOnlineRecognizerResult(result) }
        guard let text = result.pointee.text else { return "" }
        return String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    deinit {
        if let stream { SherpaOnnxDestroyOnlineStream(stream) }
        SherpaOnnxDestroyOnlineRecognizer(recognizer)
    }
}
