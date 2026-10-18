import AppIntents
import Foundation
import UniformTypeIdentifiers

struct TranscribeAudioIntent: AppIntent {
    static let title: LocalizedStringResource = "תמלול קובץ שמע"
    static let description = IntentDescription("תמלול מקומי של קובץ שמע בעברית. מילה נפתחת ומחזירה את הטקסט לשימוש בפעולה הבאה בקיצור הדרך.")
    static let openAppWhenRun = true

    @Parameter(title: "קובץ שמע", supportedTypeIdentifiers: ["public.audio"], inputConnectionBehavior: .connectToPreviousIntentResult)
    var audio: IntentFile

    static var parameterSummary: some ParameterSummary { Summary("תמלול \(\.$audio) בעברית") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try await transcribe(using: AppServices.shared))
    }

    // Keep the system adapter thin and test both IntentFile representations with an isolated service graph.
    func transcribe(using services: AppServices) async throws -> String {
        try Task.checkCancellation()
        let text: String
        if let url = audio.fileURL {
            text = try await services.transcribe(url, title: URL(fileURLWithPath: audio.filename).deletingPathExtension().lastPathComponent)
        } else {
            // Some Shortcut actions supply data rather than a file URL. Materialize it away from the UI.
            let file = audio
            let temporary = try await Task.detached {
                guard SharedAudioStorage.accepts(filename: file.filename) else { throw IntegrationError.unsupportedAudio }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(URL(fileURLWithPath: file.filename).lastPathComponent)
                do { try file.data.write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication) }
                catch { try? FileManager.default.removeItem(at: folder); throw error }
                return url
            }.value
            defer { try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent()) }
            text = try await services.transcribe(temporary, title: temporary.deletingPathExtension().lastPathComponent)
        }
        return text
    }
}

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "התחלת הקלטה"
    static let description = IntentDescription("פותח את מילה ומתחיל הקלטה ותמלול בעברית במכשיר. נדרשת הרשאת מיקרופון.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await AppServices.shared.startRecording()
        return .result()
    }
}

struct OpenLatestTranscriptIntent: AppIntent {
    static let title: LocalizedStringResource = "פתיחת התמלול האחרון"
    static let description = IntentDescription("פותח במילה את התמלול האחרון שנשמר במכשיר.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await AppServices.shared.openLatestTranscript()
        return .result()
    }
}

struct MilaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRecordingIntent(), phrases: ["התחל הקלטה ב-\(.applicationName)"], shortTitle: "התחלת הקלטה", systemImageName: "mic.fill")
        AppShortcut(intent: TranscribeAudioIntent(), phrases: ["תמלל קובץ עם \(.applicationName)"], shortTitle: "תמלול קובץ שמע", systemImageName: "waveform")
        AppShortcut(intent: OpenLatestTranscriptIntent(), phrases: ["פתח תמלול אחרון ב-\(.applicationName)"], shortTitle: "התמלול האחרון", systemImageName: "doc.text")
    }
}
