import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptDetailView: View {
    @State var transcript: Transcript
    let store: TranscriptStore
    @State private var editing: Transcript?
    @State private var exporting = false
    @State private var error: String?
    @ScaledMetric(relativeTo: .body) private var transcriptSize = 21

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(transcript.title).font(.largeTitle.bold())
                    HStack {
                        Text(transcript.createdAt, format: .dateTime.day().month(.wide).year())
                        Text("·")
                        Text(transcript.duration.clockText).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                    }.font(.subheadline).foregroundStyle(.secondary)
                    if !transcript.isComplete {
                        Label("תמלול חלקי — ההקלטה או הייבוא לא הושלמו.", systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(Theme.accent)
                    }
                }
                if let url = store.audioURL(for: transcript), FileManager.default.fileExists(atPath: url.path) {
                    AudioPlaybackView(url: url)
                }
                Text(transcript.text.isEmpty ? "לא זוהה דיבור. אפשר להאזין לשמע, אם נשמר, או לערוך את הטקסט." : transcript.text)
                    .font(.system(size: transcriptSize)).lineSpacing(10).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
                Text("תמלול אוטומטי עשוי לכלול טעויות. אפשר לערוך לפני השיתוף.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("התמלול שלך").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { editing = transcript } label: { Image(systemName: "pencil") }.accessibilityLabel("עריכת התמלול")
                Menu {
                    ShareLink(item: transcript.text) { Label("שיתוף טקסט", systemImage: "square.and.arrow.up") }
                    if let audioURL = store.audioURL(for: transcript), FileManager.default.fileExists(atPath: audioURL.path) {
                        ShareLink(item: audioURL) { Label("שיתוף ההקלטה", systemImage: "waveform") }
                    }
                    Button { exporting = true } label: { Label("ייצוא קובץ טקסט", systemImage: "doc.badge.arrow.up") }
                } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("שיתוף וייצוא")
            }
        }
        .sheet(item: $editing) { value in
            EditTranscriptView(transcript: value, store: store) { transcript = $0 }
        }
        .fileExporter(isPresented: $exporting, document: TranscriptDocument(text: transcript.text), contentType: .plainText, defaultFilename: transcript.title) { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
        .alert("הייצוא נכשל", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("אישור", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct TranscriptDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct EditTranscriptView: View {
    @State var transcript: Transcript
    let store: TranscriptStore
    let onSave: (Transcript) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                TextField("כותרת", text: $transcript.title).font(.title2.bold())
                Divider()
                TextEditor(text: $transcript.text).font(.title3).scrollContentBackground(.hidden)
                    .accessibilityLabel("טקסט התמלול")
            }.padding(24).background(Theme.background)
            .navigationTitle("עריכת תמלול").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        do { try store.save(transcript); onSave(transcript); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(transcript.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("לא ניתן לשמור", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("אישור", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}

@MainActor @Observable
private final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var isPreparing = false
    var error: String?
    private var player: AVAudioPlayer?
    private var activationID = UUID()

    func toggle(_ url: URL) async {
        guard !isPreparing else { return }
        if isPlaying { stop(); return }
        let request = UUID()
        activationID = request
        isPreparing = true
        error = nil
        do {
            try await AudioSessionController.shared.activate(for: .playback)
            // The user may have left the view while the hardware session was activating.
            guard activationID == request else { return }
            if player == nil {
                player = try AVAudioPlayer(contentsOf: url)
                player?.delegate = self
            }
            guard player?.play() == true else { throw VoiceError.invalidAudio }
            isPreparing = false
            isPlaying = true
        } catch {
            guard activationID == request else { return }
            self.error = error.localizedDescription
            stop()
        }
    }

    func stop() {
        guard isPlaying || isPreparing else { return }
        activationID = UUID()
        player?.pause()
        isPlaying = false
        isPreparing = false
        AudioSessionController.shared.deactivateInBackground()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

private struct AudioPlaybackView: View {
    let url: URL
    @State private var playback = AudioPlayback()
    var body: some View {
        VStack(alignment: .leading) {
            Button { Task { await playback.toggle(url) } } label: {
                Label(playback.isPreparing ? "מכין את ההקלטה…" : playback.isPlaying ? "השהיית ההקלטה" : "האזנה להקלטה", systemImage: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }.disabled(playback.isPreparing)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            if let error = playback.error { Text(error).font(.caption).foregroundStyle(Theme.accent) }
        }.onDisappear { playback.stop() }
    }
}
