import XCTest
@testable import HebrewVoice

@MainActor
final class ReviewPromptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func transcript(daysAgo: Int = 0, complete: Bool = true, text: String = "שלום") -> Transcript {
        var value = Transcript(title: "בדיקה")
        value.createdAt = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        value.isComplete = complete
        value.text = text
        return value
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "ReviewPromptTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    func testRequiresThreeCompletedTranscriptionsAcrossTwoDays() {
        withDefaults { defaults in
            let policy = ReviewPromptPolicy(defaults: defaults)
            let first = transcript()
            let sameDay = [first, transcript(), transcript()]
            XCTAssertFalse(policy.claimRequest(afterViewing: first.id, transcripts: sameDay, version: "1.1", now: now, calendar: calendar))
            let twoDays = [first, transcript(daysAgo: 1)]
            XCTAssertFalse(policy.claimRequest(afterViewing: first.id, transcripts: twoDays, version: "1.1", now: now, calendar: calendar))
            XCTAssertTrue(policy.claimRequest(afterViewing: first.id, transcripts: twoDays + [transcript()], version: "1.1", now: now, calendar: calendar))
        }
    }

    func testPartialBlankAndFutureTranscriptionsDoNotCount() {
        withDefaults { defaults in
            let policy = ReviewPromptPolicy(defaults: defaults)
            let first = transcript()
            let library = [first, transcript(daysAgo: 1), transcript(complete: false), transcript(text: " \n\t "), transcript(daysAgo: -1)]
            XCTAssertFalse(policy.claimRequest(afterViewing: first.id, transcripts: library, version: "1.1", now: now, calendar: calendar))
        }
    }

    func testViewedTranscriptMustStillExistAndBeCompleteWithText() {
        withDefaults { defaults in
            let policy = ReviewPromptPolicy(defaults: defaults)
            let valid = [transcript(), transcript(), transcript(daysAgo: 1)]
            XCTAssertFalse(policy.claimRequest(afterViewing: UUID(), transcripts: valid, version: "1.1", now: now, calendar: calendar))
            for invalid in [transcript(complete: false), transcript(text: "")] {
                XCTAssertFalse(policy.claimRequest(afterViewing: invalid.id, transcripts: valid + [invalid], version: "1.1", now: now, calendar: calendar))
            }
            XCTAssertTrue(policy.claimRequest(afterViewing: valid[0].id, transcripts: valid, version: "1.1", now: now, calendar: calendar))
        }
    }

    func testAttemptPersistsAndSameVersionCannotPromptAgain() {
        withDefaults { defaults in
            let library = [transcript(), transcript(), transcript(daysAgo: 1)]
            XCTAssertTrue(ReviewPromptPolicy(defaults: defaults).claimRequest(afterViewing: library[0].id, transcripts: library, version: "1.1", now: now, calendar: calendar))
            let reloaded = ReviewPromptPolicy(defaults: defaults)
            XCTAssertFalse(reloaded.claimRequest(afterViewing: library[0].id, transcripts: library, version: "1.1", now: now.addingTimeInterval(365 * 86_400), calendar: calendar))
            XCTAssertEqual(Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("reviewPrompt.") }),
                           ["reviewPrompt.lastAttemptVersion", "reviewPrompt.lastAttemptDate"])
        }
    }

    func testNewVersionWaitsNinetyDaysAndClockRollbackDoesNotBypassCooldown() {
        withDefaults { defaults in
            let library = [transcript(), transcript(), transcript(daysAgo: 1)]
            let policy = ReviewPromptPolicy(defaults: defaults)
            XCTAssertTrue(policy.claimRequest(afterViewing: library[0].id, transcripts: library, version: "1.1", now: now, calendar: calendar))
            for elapsed: TimeInterval in [-86_400, 0, 90 * 86_400 - 1] {
                XCTAssertFalse(policy.claimRequest(afterViewing: library[0].id, transcripts: library, version: "1.2", now: now.addingTimeInterval(elapsed), calendar: calendar))
            }
            XCTAssertTrue(policy.claimRequest(afterViewing: library[0].id, transcripts: library, version: "1.2", now: now.addingTimeInterval(90 * 86_400), calendar: calendar))
        }
    }

    func testEmptyVersionDoesNotConsumeAttempt() {
        withDefaults { defaults in
            let library = [transcript(), transcript(), transcript(daysAgo: 1)]
            let policy = ReviewPromptPolicy(defaults: defaults)
            XCTAssertFalse(policy.claimRequest(afterViewing: library[0].id, transcripts: library, version: "", now: now, calendar: calendar))
            XCTAssertNil(defaults.object(forKey: "reviewPrompt.lastAttemptDate"))
            XCTAssertTrue(policy.claimRequest(afterViewing: library[0].id, transcripts: library, version: "1.1", now: now, calendar: calendar))
        }
    }
}
