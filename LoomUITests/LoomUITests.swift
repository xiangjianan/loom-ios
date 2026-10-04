import XCTest
import UIKit

@MainActor final class LoomUITests: XCTestCase {
    func testPhoneTabsSwipeComposerAndSettings() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPad uses parallel columns")
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let openAI = app.buttons["model-tab-OpenAI"]
        let claude = app.buttons["model-tab-Claude"]
        XCTAssertTrue(openAI.waitForExistence(timeout: 10))
        claude.tap()
        XCTAssertTrue(claude.isSelected)
        app.swipeRight()
        XCTAssertTrue(openAI.isSelected)
        let prompt = app.textFields["prompt-field"]
        XCTAssertTrue(prompt.exists)
        prompt.tap()
        prompt.typeText("继续思考")
        XCTAssertTrue(app.buttons["send-button"].isEnabled)
        app.buttons["模型设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(prompt.exists)
    }

    func testPadDisplaysParallelAnswersAndFixedComposer() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Parallel columns are an iPad layout")
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10))
        let left = app.scrollViews["thread-OpenAI"]
        let right = app.scrollViews["thread-Claude"]
        XCTAssertTrue(left.exists && right.exists)
        XCTAssertTrue(left.isHittable && right.isHittable)
        XCTAssertLessThan(left.frame.minX, right.frame.minX)
        XCTAssertFalse(app.buttons["model-tab-OpenAI"].exists)
        XCTAssertTrue(app.textFields["prompt-field"].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(left.isHittable && right.isHittable)
        XCTAssertLessThan(left.frame.minX, right.frame.minX)
        XCTAssertTrue(app.textFields["prompt-field"].exists)
        XCUIDevice.shared.orientation = .portrait
    }

    func testSelectingTextAutomaticallyAddsQuote() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let answer = app.textViews.firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        answer.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.04)).press(forDuration: 1.2)
        let hint = app.staticTexts["selection-hint"]
        let quoted = NSPredicate(format: "label CONTAINS %@", "段引用")
        expectation(for: quoted, evaluatedWith: hint)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.scrollViews["quote-tray"].exists)
    }
}
