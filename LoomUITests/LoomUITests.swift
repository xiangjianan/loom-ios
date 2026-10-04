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

    func testNativeSelectionMenuDoesNotCreateQuote() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let answer = app.textViews.firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        answer.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.04)).press(forDuration: 1.2)
        XCTAssertFalse(app.scrollViews["quote-tray"].exists)
        let copy = app.menuItems.matching(NSPredicate(format: "label IN %@", ["Copy", "拷贝", "复制"])).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.otherElements["UIContextMenuContentView"].exists)
        for _ in 0..<4 where !app.menuItems["高亮"].exists {
            app.buttons.matching(NSPredicate(format: "label == %@", "Next Page")).allElementsBoundByIndex.last?.tap()
        }
        XCTAssertTrue(app.menuItems["高亮"].waitForExistence(timeout: 5))
        app.menuItems["高亮"].tap()
        XCTAssertTrue(app.scrollViews["quote-tray"].waitForExistence(timeout: 5))
    }
    func testSingleTapSentenceTogglesHighlight() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let answer = app.textViews.firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        let point = answer.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.04))
        point.tap()
        XCTAssertTrue(app.scrollViews["quote-tray"].waitForExistence(timeout: 5))
        point.tap()
        XCTAssertFalse(app.scrollViews["quote-tray"].exists)
    }
    func testDoubleTapSentenceSettingAndRemoval() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        app.buttons["workspace-menu"].tap()
        app.buttons["模型设置"].tap()
        app.swipeUp()
        let mode = app.buttons["sentence-highlight-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.tap()
        app.buttons["双击句子"].tap()
        app.buttons["完成"].tap()
        let answer = app.textViews.firstMatch
        let point = answer.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.04))
        point.tap()
        XCTAssertFalse(app.scrollViews["quote-tray"].exists)
        point.doubleTap()
        XCTAssertTrue(app.scrollViews["quote-tray"].waitForExistence(timeout: 5))
        point.doubleTap()
        XCTAssertFalse(app.scrollViews["quote-tray"].exists)
        point.doubleTap()
        XCTAssertTrue(app.scrollViews["quote-tray"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "移除引用：")).firstMatch.tap()
        XCTAssertFalse(app.scrollViews["quote-tray"].exists)
    }

    func testSVGAppearsInlineAndSentencesAreIndependent() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-svg"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["svg-image"].waitForExistence(timeout: 10))
        let answer = app.textViews.firstMatch
        XCTAssertFalse(answer.value.debugDescription.contains("<svg"))
        let point = answer.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.025))
        point.tap()
        XCTAssertTrue(app.scrollViews["quote-tray"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["第一句，"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testHistoryDeletionRequiresExplicitConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        app.buttons["workspace-menu"].tap()
        app.buttons["历史对话"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let originalLabel = row.label
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["取消"].exists)
        XCTAssertTrue(alert.buttons["删除"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        alert.buttons["取消"].tap()
        XCTAssertEqual(row.label, originalLabel)
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["删除"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", originalLabel)).firstMatch.exists)
    }

    func testTappingAdjacentHighlightsMergesAndCancelsWholeGroup() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-svg"]
        app.launch()
        let answer = app.textViews.firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        func tap(_ x: CGFloat) {
            answer.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: 11)).tap()
        }
        tap(22)
        XCTAssertTrue(app.staticTexts["第一句，"].waitForExistence(timeout: 5))
        tap(110)
        XCTAssertTrue(app.staticTexts["第一句，逗号、顿号和冒号："].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "移除引用：")).count, 1)
        tap(110)
        XCTAssertTrue(app.scrollViews["quote-tray"].waitForNonExistence(timeout: 5))
    }

    func testPadReadingScrollHidesAndRestoresChrome() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Parallel reading is an iPad interaction")
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-long"]
        app.launch()
        let tab = app.buttons["model-tab-OpenAI"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        let scroll = app.scrollViews["thread-OpenAI"]
        let height = scroll.frame.height
        scroll.swipeUp()
        XCTAssertTrue(tab.waitForNonExistence(timeout: 5))
        XCTAssertGreaterThan(scroll.frame.height, height + 50)
        scroll.swipeDown()
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["prompt-field"].exists)
    }

    func testReadingScrollHidesChromeAndReverseOrModelSwipeRestoresIt() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Model paging is an iPhone interaction")
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-long"]
        app.launch()
        let tab = app.buttons["model-tab-OpenAI"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        let scroll = app.scrollViews["thread-OpenAI"]
        let originalHeight = scroll.frame.height
        scroll.swipeUp()
        XCTAssertTrue(tab.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.textFields["prompt-field"].exists)
        XCTAssertGreaterThan(scroll.frame.height, originalHeight + 50)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        scroll.swipeDown()
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["prompt-field"].exists)
        scroll.swipeUp()
        XCTAssertTrue(tab.waitForNonExistence(timeout: 5))
        scroll.swipeLeft()
        XCTAssertTrue(app.buttons["model-tab-Claude"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["model-tab-Claude"].isSelected)
        XCTAssertTrue(app.textFields["prompt-field"].exists)
    }

    func testDraggingSelectionHandleScrollsLongAnswer() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-long"]
        app.launch()
        let answer = app.textViews.firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        let origin = answer.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: 88, dy: 11)).press(forDuration: 1.2)
        let before = answer.frame.minY
        let edge = app.scrollViews["thread-OpenAI"].coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.98))
        origin.withOffset(CGVector(dx: 94, dy: 28)).press(forDuration: 0.2, thenDragTo: edge, withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertLessThan(answer.frame.minY, before - 60)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
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

    func testRenderedMarkdownSupportsSentenceHighlight() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-markdown"]
        app.launch()
        let answer = app.textViews.firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        XCTAssertFalse(answer.value.debugDescription.contains("# 从一个"))
        answer.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.04)).tap()
        XCTAssertTrue(app.scrollViews["quote-tray"].waitForExistence(timeout: 5))
    }
}
