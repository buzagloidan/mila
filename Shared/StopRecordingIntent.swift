import AppIntents
import Foundation

struct StopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "סיום ושמירת הקלטה"
    static var isDiscoverable: Bool = false

    @Parameter(title: "מזהה הקלטה") var sessionID: String

    init() {}
    init(sessionID: UUID) { self.sessionID = sessionID.uuidString }

    func perform() async throws -> some IntentResult {
        #if MILA_APP
        guard let id = UUID(uuidString: sessionID) else { throw IntegrationError.invalidSharedItem }
        await AppServices.shared.stopRecording(sessionID: id)
        #else
        // LiveActivityIntent is dispatched to the containing app, which implements the action above.
        try unavailableOutsideApp()
        #endif
        return .result()
    }

    private func unavailableOutsideApp() throws { throw LiveActivityActionError() }
}

private struct LiveActivityActionError: LocalizedError {
    var errorDescription: String? { "יש לפתוח את מילה כדי לסיים את ההקלטה." }
}
