import SwiftUI
import AVFoundation

/// Test-only sender: exercises the real system share sheet in a separate app process.
@main
struct DocumentProbeApp: App {
    private let wav: URL
    private let m4a: URL

    init() {
        let args = ProcessInfo.processInfo.arguments
        let title = args.last ?? "document-probe"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        wav = directory.appendingPathComponent(title + ".wav")
        m4a = directory.appendingPathComponent(title + ".m4a")
        try! FileManager.default.copyItem(at: Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav")!, to: wav)
        let input = try! AVAudioFile(forReading: wav)
        let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length))!
        try! input.read(into: buffer)
        let output = try! AVAudioFile(forWriting: m4a, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: input.processingFormat.sampleRate,
            AVNumberOfChannelsKey: input.processingFormat.channelCount,
            AVEncoderBitRateKey: 32_000
        ])
        try! output.write(from: buffer)
    }

    var body: some Scene {
        WindowGroup {
            VStack {
                ShareLink("Share WAV", item: wav).accessibilityIdentifier("shareWAV")
                ShareLink("Share M4A", item: m4a).accessibilityIdentifier("shareM4A")
            }
        }
    }
}
