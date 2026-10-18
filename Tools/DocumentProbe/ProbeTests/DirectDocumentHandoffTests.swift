import XCTest

final class DirectDocumentHandoffTests: XCTestCase {
    @MainActor
    func testWAVOpensTerminatedAppAndTranscribes() {
        let mila = XCUIApplication(bundleIdentifier: "com.hebrewvoice.mila")
        mila.terminate()
        shareAndVerify(button: "shareWAV")
    }

    @MainActor
    func testM4AOpensAppAndTranscribes() {
        shareAndVerify(button: "shareM4A")
    }

    @MainActor
    private func shareAndVerify(button: String) {
        let title = "mila-handoff-" + UUID().uuidString
        let probe = XCUIApplication()
        probe.launchArguments = [title]
        probe.launch()
        probe.buttons[button].tap()
        let destination = probe.cells.matching(NSPredicate(format: "label == %@", "מילה")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10), probe.debugDescription)
        guard destination.exists else { return }
        destination.tap()
        let mila = XCUIApplication(bundleIdentifier: "com.hebrewvoice.mila")
        XCTAssertTrue(mila.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(mila.navigationBars[title].waitForExistence(timeout: 10), mila.debugDescription)
        XCTAssertTrue(mila.staticTexts["שלום."].waitForExistence(timeout: 15), mila.debugDescription)
        XCTAssertFalse(mila.buttons["שמירה במילה"].exists)
    }
}
