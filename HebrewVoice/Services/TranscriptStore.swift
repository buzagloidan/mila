import Foundation
import Observation

@MainActor @Observable
final class TranscriptStore {
    private(set) var transcripts: [Transcript] = []
    var errorMessage: String?
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcripts", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            var localURL = self.directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try localURL.setResourceValues(values)
            let files = try FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                do { transcripts.append(try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: file))) }
                catch { errorMessage = "לא ניתן לקרוא אחד מהתמלולים השמורים. הקובץ נשמר במכשיר ולא נמחק." }
            }
            transcripts.sort { $0.createdAt > $1.createdAt }
        } catch { errorMessage = "לא ניתן לפתוח את התמלולים: \(error.localizedDescription)" }
    }

    func save(_ transcript: Transcript) throws {
        let data = try JSONEncoder().encode(transcript)
        let url = directory.appendingPathComponent("\(transcript.id).json")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if let index = transcripts.firstIndex(where: { $0.id == transcript.id }) { transcripts[index] = transcript }
        else { transcripts.insert(transcript, at: 0) }
    }

    func delete(_ transcript: Transcript) throws {
        // Delete the metadata last so a failed audio deletion remains recoverable.
        if let audio = audioURL(for: transcript), FileManager.default.fileExists(atPath: audio.path) {
            try FileManager.default.removeItem(at: audio)
        }
        try FileManager.default.removeItem(at: directory.appendingPathComponent("\(transcript.id).json"))
        transcripts.removeAll { $0.id == transcript.id }
    }

    func audioURL(for transcript: Transcript) -> URL? {
        transcript.audioFilename.map { directory.appendingPathComponent($0) }
    }
}
