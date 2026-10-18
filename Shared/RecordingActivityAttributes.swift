import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Status: String, Codable { case recording, saved, stopped }
        var status: Status
    }
    let sessionID: UUID
    let startedAt: Date
}
