import Foundation

/// Eligibility comes from the existing local library. Only request attempts are persisted;
/// StoreKit does not tell us whether its dialog appeared or a rating was submitted.
@MainActor
final class ReviewPromptPolicy {
    static let reviewURL = URL(string: "https://apps.apple.com/app/id6824172039?action=write-review")!
    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    private static let cooldown: TimeInterval = 90 * 24 * 60 * 60
    private let defaults: UserDefaults
    private let versionKey = "reviewPrompt.lastAttemptVersion"
    private let dateKey = "reviewPrompt.lastAttemptDate"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Call immediately before requesting StoreKit, after the presentation delay and UI checks.
    func claimRequest(afterViewing id: UUID, transcripts: [Transcript], version: String? = nil,
                      now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let version = version ?? Self.appVersion
        guard !version.isEmpty, defaults.string(forKey: versionKey) != version else { return false }
        if let lastAttempt = defaults.object(forKey: dateKey) as? Date,
           now.timeIntervalSince(lastAttempt) < Self.cooldown { return false }

        let completed = transcripts.filter {
            $0.isComplete && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.createdAt <= now
        }
        guard completed.contains(where: { $0.id == id }), completed.count >= 3,
              Set(completed.map { calendar.startOfDay(for: $0.createdAt) }).count >= 2 else { return false }

        // Record the attempt even if iOS elects not to display the prompt.
        defaults.set(version, forKey: versionKey)
        defaults.set(now, forKey: dateKey)
        return true
    }
}
