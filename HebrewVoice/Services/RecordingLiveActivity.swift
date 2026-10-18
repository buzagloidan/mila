import ActivityKit
import Foundation

@MainActor
final class RecordingLiveActivity {
    private var activity: Activity<RecordingActivityAttributes>?

    func start(sessionID: UUID, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let attributes = RecordingActivityAttributes(sessionID: sessionID, startedAt: startedAt)
            activity = try Activity.request(attributes: attributes,
                content: ActivityContent(state: RecordingActivityAttributes.ContentState(status: .recording), staleDate: nil), pushType: nil)
        } catch {
            // An unavailable Live Activity must not interrupt an ordinary in-app microphone recording.
            // The system microphone indicator still identifies microphone use.
        }
    }

    func end(saved: Bool) async {
        guard let activity else { return }
        self.activity = nil
        let state = RecordingActivityAttributes.ContentState(status: saved ? .saved : .stopped)
        await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
    }

    static func endStaleActivity(sessionID: UUID? = nil) async {
        for activity in Activity<RecordingActivityAttributes>.activities where sessionID == nil || activity.attributes.sessionID == sessionID {
            let state = RecordingActivityAttributes.ContentState(status: .stopped)
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
