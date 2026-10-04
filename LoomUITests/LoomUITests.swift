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
        app.buttons["workspace-menu"].tap()
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
        XCTAssertTrue(app.buttons["model-tab-OpenAI"].exists)
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
        XCTAssertTrue(app.scrollViews["quote-tray"].waitForExistence(timeout: 5))
    }
    func testComposerExpandsAndKeepsSendAtBottom() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let prompt = app.textFields["prompt-field"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        let send = app.buttons["send-button"]
        XCTAssertFalse(send.isEnabled)
        // Accessibility reports the editable text bounds, excluding the 10pt vertical inset.
        XCTAssertEqual(prompt.frame.height + 20, send.frame.height, accuracy: 3)
        prompt.tap()
        prompt.typeText("第一行\n第二行\n第三行")
        XCTAssertGreaterThan(prompt.frame.height, send.frame.height)
        XCTAssertEqual(prompt.frame.maxY + 10, send.frame.maxY, accuracy: 3)
        XCTAssertTrue(send.isEnabled)
    }

    func testProviderPresetAndAutomaticDiscovery() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-test-discovery"]
        app.launch()
        app.buttons["workspace-menu"].tap()
        app.buttons["模型设置"].tap()
        app.buttons["添加模型"].tap()
        let picker = app.buttons["provider-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["DeepSeek"].tap()
        XCTAssertEqual(app.textFields["model-endpoint"].value as? String, "https://api.deepseek.com/v1")
        let key = app.secureTextFields["api-key"]
        key.tap()
        key.typeText("ui-fixture-key")
        XCTAssertTrue(app.buttons["online-model-picker"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["model-id"].value as? String, "fixture-chat")
    }

    func testRenderedMarkdownStillSupportsNativeHighlight() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-markdown"]
        app.launch()
        let answer = app.textViews.firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        XCTAssertFalse(answer.value.debugDescription.contains("# 从一个"))
        answer.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.04)).press(forDuration: 1.2)
        XCTAssertTrue(app.scrollViews["quote-tray"].waitForExistence(timeout: 5))
    }

}
