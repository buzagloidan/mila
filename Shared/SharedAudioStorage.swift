import Foundation
import UniformTypeIdentifiers

enum IntegrationError: LocalizedError {
    case sharedStorageUnavailable, unsupportedAudio, invalidSharedItem, busy, noTranscript, interrupted

    var errorDescription: String? {
        switch self {
        case .sharedStorageUnavailable: return "לא ניתן לפתוח את תיבת השמע המשותף. נסו לפתוח מחדש את מילה."
        case .unsupportedAudio: return "הקובץ אינו קובץ שמע נתמך. נסו לשתף הקלטה בפורמט M4A או WAV."
        case .invalidSharedItem: return "לא ניתן לקרוא את ההקלטה ששותפה. נסו לשתף אותה שוב."
        case .busy: return "כבר מתבצעת הקלטה או פעולת תמלול במילה. סיימו אותה ונסו שוב."
        case .noTranscript: return "אין עדיין תמלולים שמורים במילה."
        case .interrupted: return "התמלול לא הושלם. התוצאה החלקית נשמרה במילה."
        }
    }
}

struct SharedAudioItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let filename: String
    let createdAt: Date
}

/// Durable incoming-audio queue, compatible with entries from earlier Share Extension builds.
/// Each entry becomes visible atomically; attachment filenames never become directory paths.
struct SharedAudioStorage: Sendable {
    static let groupIdentifier = "group.com.hebrewvoice.mila"
    let root: URL

    init(root: URL? = nil) throws {
        guard let root = root ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupIdentifier) else {
            throw IntegrationError.sharedStorageUnavailable
        }
        self.root = root.appendingPathComponent("SharedAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        var location = self.root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try location.setResourceValues(values)
    }

    static func accepts(filename: String) -> Bool {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return ["m4a", "wav", "mp3", "caf", "aac", "aif", "aiff", "flac", "ogg", "opus"].contains(ext)
            || UTType(filenameExtension: ext)?.conforms(to: .audio) == true
    }

    func enqueue(file source: URL, suggestedName: String? = nil) throws -> SharedAudioItem {
        let name = Self.cleanName(suggestedName ?? source.lastPathComponent)
        let usableName = Self.accepts(filename: name) ? name : source.lastPathComponent
        guard Self.accepts(filename: usableName) else { throw IntegrationError.unsupportedAudio }
        let ext = URL(fileURLWithPath: usableName).pathExtension.lowercased()
        let id = UUID()
        let staging = root.appendingPathComponent(".staging-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let item = SharedAudioItem(id: id, title: String(URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.prefix(120)),
                                  filename: "audio.\(ext)", createdAt: Date())
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let audio = staging.appendingPathComponent(item.filename)
        try FileManager.default.copyItem(at: source, to: audio)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: audio.path)
        try JSONEncoder().encode(item).write(to: staging.appendingPathComponent("item.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try FileManager.default.moveItem(at: staging, to: root.appendingPathComponent(id.uuidString, isDirectory: true))
        return item
    }

    func items() throws -> [SharedAudioItem] {
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return try folders.compactMap { folder in
            guard let id = UUID(uuidString: folder.lastPathComponent) else { return nil }
            // A corrupt entry remains on disk and produces a visible error rather than disappearing.
            let item = try JSONDecoder().decode(SharedAudioItem.self, from: Data(contentsOf: folder.appendingPathComponent("item.json")))
            guard item.id == id else { throw IntegrationError.invalidSharedItem }
            _ = try audioURL(for: item)
            return item
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func audioURL(for item: SharedAudioItem) throws -> URL {
        guard item.filename == URL(fileURLWithPath: item.filename).lastPathComponent,
              item.filename.hasPrefix("audio."), Self.accepts(filename: item.filename) else { throw IntegrationError.invalidSharedItem }
        let directory = root.appendingPathComponent(item.id.uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(item.filename)
        guard url.resolvingSymlinksInPath().deletingLastPathComponent() == directory.resolvingSymlinksInPath(),
              FileManager.default.fileExists(atPath: url.path) else { throw IntegrationError.invalidSharedItem }
        return url
    }

    func remove(id: UUID) throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    private static func cleanName(_ name: String) -> String {
        let last = URL(fileURLWithPath: name).lastPathComponent
        let clean = String(last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return clean.isEmpty ? "הקלטה משותפת.m4a" : clean
    }
}
