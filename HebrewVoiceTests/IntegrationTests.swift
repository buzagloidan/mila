import AppIntents
import UniformTypeIdentifiers
import XCTest
@testable import HebrewVoice

final class IntegrationTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testStagedDocumentSurvivesSourceRemovalAndStorageRelaunch() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("הודעת WhatsApp.wav")
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        try FileManager.default.copyItem(at: fixture, to: source)
        let storage = try SharedAudioStorage(root: root.appendingPathComponent("group"))
        let item = try storage.enqueue(file: source)
        try FileManager.default.removeItem(at: source)
        let reloaded = try SharedAudioStorage(root: root.appendingPathComponent("group"))
        XCTAssertEqual(try reloaded.items(), [item])
        XCTAssertEqual(item.title, "הודעת WhatsApp")
        XCTAssertEqual(try Data(contentsOf: reloaded.audioURL(for: item)), try Data(contentsOf: fixture))
    }

    @MainActor
    func testOpeningDocumentAutomaticallyTranscribesAndPreservesExternalOriginal() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("הודעה.wav")
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        try FileManager.default.copyItem(at: fixture, to: source)
        let inbox = SharedInbox(repository: SharedInboxRepository(root: root.appendingPathComponent("group")))
        let services = AppServices(store: TranscriptStore(directory: root.appendingPathComponent("library")), inbox: inbox)
        await services.receiveAudioDocument(source)
        let transcript = try XCTUnwrap(services.store.transcripts.first)
        XCTAssertTrue(transcript.isComplete)
        XCTAssertTrue(transcript.text.contains("שלום"))
        XCTAssertEqual(transcript.title, "הודעה")
        XCTAssertEqual(services.navigation.request?.destination, .recorder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let pending = try await inbox.repository.items()
        XCTAssertTrue(pending.isEmpty)
    }

    @MainActor
    func testTwoIncomingDocumentsBothFinishWithoutAnotherUserAction() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        let first = root.appendingPathComponent("ראשונה.wav")
        let second = root.appendingPathComponent("שנייה.wav")
        try FileManager.default.copyItem(at: fixture, to: first)
        try FileManager.default.copyItem(at: fixture, to: second)
        let inbox = SharedInbox(repository: SharedInboxRepository(root: root.appendingPathComponent("group")))
        let services = AppServices(store: TranscriptStore(directory: root.appendingPathComponent("library")), inbox: inbox)
        let firstTask = Task { await services.receiveAudioDocument(first) }
        let secondTask = Task { await services.receiveAudioDocument(second) }
        await firstTask.value
        await secondTask.value
        await services.processPendingAudio()
        XCTAssertEqual(Set(services.store.transcripts.map(\.title)), Set(["ראשונה", "שנייה"]))
        XCTAssertTrue(services.store.transcripts.allSatisfy { $0.isComplete && $0.text.contains("שלום") })
        let pending = try await inbox.repository.items()
        XCTAssertTrue(pending.isEmpty)
    }

    @MainActor
    func testInvalidDocumentShowsErrorWithoutDeletingSource() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("document.pdf")
        try Data("not audio".utf8).write(to: source)
        let inbox = SharedInbox(repository: SharedInboxRepository(root: root.appendingPathComponent("group")))
        let services = AppServices(store: TranscriptStore(directory: root.appendingPathComponent("library")), inbox: inbox)
        await services.receiveAudioDocument(source)
        XCTAssertNotNil(inbox.errorMessage)
        XCTAssertTrue(services.store.transcripts.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testUndecodableAudioIsRetainedWithoutAutomaticRetryLoop() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("broken.wav")
        try Data("not an audio stream".utf8).write(to: source)
        let inbox = SharedInbox(repository: SharedInboxRepository(root: root.appendingPathComponent("group")))
        let services = AppServices(store: TranscriptStore(directory: root.appendingPathComponent("library")), inbox: inbox)
        await services.receiveAudioDocument(source)
        let savedIDs = services.store.transcripts.map(\.id)
        XCTAssertNotNil(inbox.errorMessage)
        let pending = try await inbox.repository.items()
        XCTAssertEqual(pending.count, 1)
        await services.processPendingAudio()
        XCTAssertEqual(services.store.transcripts.map(\.id), savedIDs)
        let remaining = try await inbox.repository.items()
        XCTAssertEqual(remaining.count, 1)
    }

    func testUnsupportedShareDoesNotLeavePendingOrStagingFiles() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try SharedAudioStorage(root: root)
        let source = root.appendingPathComponent("document.pdf")
        try Data("not audio".utf8).write(to: source)
        XCTAssertThrowsError(try storage.enqueue(file: source))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: storage.root.path).isEmpty)
    }

    func testIncompleteStagingDirectoriesAreNeverShown() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try SharedAudioStorage(root: root)
        try FileManager.default.createDirectory(at: storage.root.appendingPathComponent(".staging-\(UUID())"), withIntermediateDirectories: false)
        XCTAssertTrue(try storage.items().isEmpty)
    }

    func testUntrustedSharedMetadataCannotEscapeItsDirectory() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try SharedAudioStorage(root: root)
        let id = UUID()
        let folder = storage.root.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let item = SharedAudioItem(id: id, title: "test", filename: "../../private.wav", createdAt: Date())
        try JSONEncoder().encode(item).write(to: folder.appendingPathComponent("item.json"))
        XCTAssertThrowsError(try storage.items())
        XCTAssertThrowsError(try storage.audioURL(for: item))
    }

    @MainActor
    func testSharedAudioTranscribesLocallyBeforeSourceIsRemoved() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try SharedAudioStorage(root: root.appendingPathComponent("group"))
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        let item = try storage.enqueue(file: fixture, suggestedName: "הודעה.wav")
        let store = TranscriptStore(directory: root.appendingPathComponent("library"))
        let inbox = SharedInbox(repository: SharedInboxRepository(root: root.appendingPathComponent("group")))
        let services = AppServices(store: store, inbox: inbox)
        await inbox.refresh()
        try await services.transcribeShared(item)
        let transcript = try XCTUnwrap(store.transcripts.first)
        XCTAssertTrue(transcript.isComplete)
        XCTAssertTrue(transcript.text.contains("שלום"))
        XCTAssertEqual(transcript.sourceID, item.id)
        XCTAssertEqual(transcript.title, "הודעה")
        XCTAssertTrue(try storage.items().isEmpty)
        XCTAssertTrue(inbox.items.isEmpty)
    }

    @MainActor
    func testCompletedSharedImportIsNotDuplicatedAfterInterruptedCleanup() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try SharedAudioStorage(root: root.appendingPathComponent("group"))
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        let item = try storage.enqueue(file: fixture)
        let store = TranscriptStore(directory: root.appendingPathComponent("library"))
        var completed = Transcript(title: "כבר תומלל")
        completed.text = "שלום"
        completed.isComplete = true
        completed.sourceID = item.id
        try store.save(completed)
        let inbox = SharedInbox(repository: SharedInboxRepository(root: root.appendingPathComponent("group")))
        let services = AppServices(store: store, inbox: inbox)
        try await services.transcribeShared(item)
        XCTAssertEqual(store.transcripts, [completed])
        XCTAssertEqual(services.navigation.request?.destination, .transcript(completed.id))
        XCTAssertTrue(try storage.items().isEmpty)
    }

    @MainActor
    func testCancelledSharedImportRetainsTheSourceForRetry() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try SharedAudioStorage(root: root.appendingPathComponent("group"))
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        let item = try storage.enqueue(file: fixture)
        let store = TranscriptStore(directory: root.appendingPathComponent("library"))
        let inbox = SharedInbox(repository: SharedInboxRepository(root: root.appendingPathComponent("group")))
        let services = AppServices(store: store, inbox: inbox)
        let task = Task { try await services.transcribeShared(item) }
        // Cancel once the import has acquired the session; no microphone or timing-based sleep is needed.
        let deadline = Date().addingTimeInterval(5)
        while services.session.phase != .importing && Date() < deadline { await Task.yield() }
        guard services.session.phase == .importing else {
            task.cancel()
            _ = try? await task.value
            return XCTFail("The shared import did not start")
        }
        services.session.cancelImport()
        do { try await task.value; XCTFail("Expected a partial import") } catch { }
        XCTAssertEqual(try storage.items(), [item])
        XCTAssertFalse(try XCTUnwrap(store.transcripts.first).isComplete)
    }

    @MainActor
    func testOpenLatestTranscriptRoutesToSavedItemAndHandlesEmptyLibrary() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TranscriptStore(directory: root.appendingPathComponent("library"))
        let services = AppServices(store: store)
        XCTAssertThrowsError(try services.openLatestTranscript())
        let transcript = Transcript(title: "הרצאה")
        try store.save(transcript)
        try services.openLatestTranscript()
        XCTAssertEqual(services.navigation.request?.destination, .transcript(transcript.id))
    }

    @MainActor
    func testShortcutFileInputReturnsHebrewText() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let services = AppServices(store: TranscriptStore(directory: root.appendingPathComponent("library")))
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        let intent = TranscribeAudioIntent()
        intent.audio = IntentFile(fileURL: fixture, filename: "הודעה.wav", type: .wav)
        let text = try await intent.transcribe(using: services)
        XCTAssertTrue(text.contains("שלום"))
        XCTAssertEqual(services.store.transcripts.first?.title, "הודעה")
        XCTAssertEqual(services.navigation.request?.destination, .recorder)
    }

    @MainActor
    func testShortcutDataInputReturnsHebrewText() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let services = AppServices(store: TranscriptStore(directory: root.appendingPathComponent("library")))
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "sample-hebrew", withExtension: "wav"))
        let intent = TranscribeAudioIntent()
        intent.audio = IntentFile(data: try Data(contentsOf: fixture), filename: "קובץ מקיצור דרך.wav", type: .wav)
        let text = try await intent.transcribe(using: services)
        XCTAssertTrue(text.contains("שלום"))
        XCTAssertTrue(try XCTUnwrap(services.store.transcripts.first).isComplete)
    }

    func testLiveActivityAttributesContainNoTranscriptOrMeetingTitle() throws {
        let attributes = RecordingActivityAttributes(sessionID: UUID(), startedAt: Date())
        let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attributes)) as? [String: Any]
        XCTAssertEqual(Set(try XCTUnwrap(value).keys), Set(["sessionID", "startedAt"]))
    }
}
