import XCTest
import UIKit

@MainActor final class LoomUITests: XCTestCase {
    func testNewRoundReturnsToUserMessageInsteadOfAnswerBottom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-rounds", "--demo-next-round"]
        app.launch()
        let prompt = app.textFields["prompt-field"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        prompt.tap()
        prompt.typeText("新一轮定位测试")
        app.buttons["send-button"].tap()
        let user = app.staticTexts["新一轮定位测试"].firstMatch
        XCTAssertTrue(user.waitForExistence(timeout: 8))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            user.isHittable && user.frame.minY < app.frame.height * 0.4
        }, object: user)], timeout: 8) == .completed)
        sleep(1)
        XCTAssertLessThan(user.frame.minY, app.frame.height * 0.4)
        app.buttons["model-tab-Claude"].tap()
        XCTAssertTrue(app.buttons["model-tab-Claude"].isSelected)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        let second = app.scrollViews["thread-Claude"].staticTexts["新一轮定位测试"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            second.isHittable && second.frame.minY < app.frame.height * 0.4
        }, object: second)], timeout: 5) == .completed)
    }

    func testNativeScrollIndicatorRemainsDraggableBesideRoundTicks() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-rounds"]
        app.launch()
        let reader = app.scrollViews["thread-OpenAI"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        reader.swipeUp()
        let indicator = reader.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "Vertical scroll bar")).firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: 3))
        let thumb = indicator.children(matching: .other).firstMatch
        let target = thumb.exists ? thumb : indicator
        let first = reader.staticTexts["继续讨论第1轮的问题"]
        let previous = first.frame.minY
        let before = XCTAttachment(screenshot: app.screenshot()); before.lifetime = .keepAlways; add(before)
        // The system paints a 3 pt thumb; use its expanded finger hit region.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: target.frame.midX - 6, dy: target.frame.midY))
        let end = origin.withOffset(CGVector(dx: target.frame.midX - 6, dy: reader.frame.minY + reader.frame.height * 0.8))
        start.press(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        let after = XCTAttachment(screenshot: app.screenshot()); after.lifetime = .keepAlways; add(after)
        XCTAssertTrue(!first.exists || first.frame.minY < previous - 100, "previous: \(previous), current: \(first.frame.minY), thumb: \(target.frame), reader: \(reader.frame), start: \(start.screenPoint), end: \(end.screenPoint)")
    }

    func testNativeMenuRemainsReadableAfterScrolling() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Phone chrome")
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-rounds"]
        app.launch()
        let reader = app.scrollViews["thread-OpenAI"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        reader.swipeUp()
        reader.swipeUp()
        reader.swipeDown()
        XCTAssertTrue(app.buttons["workspace-menu"].waitForExistence(timeout: 5))
        app.buttons["workspace-menu"].tap()
        XCTAssertTrue(app.buttons["历史对话"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["历史对话"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testBackupMenuUsesNativeFilesExport() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-rounds"]
        app.launch()
        XCTAssertTrue(app.buttons["workspace-menu"].waitForExistence(timeout: 10))
        app.buttons["workspace-menu"].tap()
        app.buttons["备份（导入 / 导出）"].tap()
        XCTAssertTrue(app.navigationBars["备份"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["backup-export"].exists)
        XCTAssertTrue(app.buttons["backup-import"].exists)
        app.buttons["backup-export"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }

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

    func testRoundTicksTapScrubAndExpandSentReferences() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-rounds"]
        app.launch()
        let scroll = app.scrollViews["thread-OpenAI"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["轮次导航"].exists)
        let firstMessage = scroll.staticTexts["继续讨论第1轮的问题"]
        let initialLayout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in firstMessage.frame.minX >= scroll.frame.minX + 39 }, object: firstMessage)
        XCTAssertEqual(XCTWaiter.wait(for: [initialLayout], timeout: 5), .completed)
        let messageLeft = firstMessage.frame.minX
        scroll.swipeUp()
        let third = app.buttons["round-tick-3"]
        XCTAssertTrue(third.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        third.tap()
        let message = scroll.staticTexts["继续讨论第3轮的问题"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        let arrived = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in message.isHittable }, object: message)
        XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 5), .completed)
        XCTAssertEqual(message.frame.minX, messageLeft, accuracy: 2, "Round ticks must not shift the message horizontally")
        let disclosure = scroll.descendants(matching: .any)["message-references-3"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        disclosure.tap()
        XCTAssertTrue(scroll.staticTexts["这是上一轮保留的高亮观点。"].waitForExistence(timeout: 3))
        let expandedScreenshot = XCTAttachment(screenshot: app.screenshot()); expandedScreenshot.lifetime = .keepAlways; add(expandedScreenshot)
        scroll.swipeUp()
        let fourth = app.buttons["round-tick-4"]
        XCTAssertTrue(fourth.waitForExistence(timeout: 3))
        fourth.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.3, thenDragTo: app.buttons["round-tick-1"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.5)
        let draggedScreenshot = XCTAttachment(screenshot: app.screenshot()); draggedScreenshot.lifetime = .keepAlways; add(draggedScreenshot)
        let firstRound = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            scroll.staticTexts["继续讨论第1轮的问题"].isHittable
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [firstRound], timeout: 5), .completed)
    }

    func testEachModelRestoresItsOwnReadingOffset() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Paging is an iPhone interaction")
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-rounds"]
        app.launch()
        func readingTop(_ reader: XCUIElement) -> CGFloat {
            let menu = app.buttons["workspace-menu"]
            return max(reader.frame.minY, menu.exists ? menu.frame.maxY + 8 : reader.frame.minY)
        }
        let first = app.scrollViews["thread-OpenAI"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.swipeUp()
        let firstAnswer = first.textViews.matching(NSPredicate(format: "label == %@", "第1轮 · 第8段：这是一段可滚动的多轮回答。每个模型应该记住自己的阅读位置，轮次标记可以直接跳转。")).firstMatch
        Thread.sleep(forTimeInterval: 0.6)
        let offsetA = readingTop(first) - firstAnswer.frame.minY
        let leftA = firstAnswer.frame.minX
        first.swipeLeft()
        XCTAssertTrue(app.buttons["model-tab-Claude"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["model-tab-Claude"].isSelected)
        let second = app.scrollViews["thread-Claude"]
        second.swipeUp()
        second.swipeUp()
        let secondAnswer = second.textViews.matching(NSPredicate(format: "label == %@", "第2轮 · 第3段：这是一段可滚动的多轮回答。每个模型应该记住自己的阅读位置，轮次标记可以直接跳转。")).firstMatch
        Thread.sleep(forTimeInterval: 0.6)
        let offsetB = readingTop(second) - secondAnswer.frame.minY
        let leftB = secondAnswer.frame.minX
        second.swipeRight()
        let restoredA = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs((readingTop(first) - firstAnswer.frame.minY) - offsetA) < 25 && abs(firstAnswer.frame.minX - leftA) < 2
        }, object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [restoredA], timeout: 5), .completed, "Expected \(offsetA), actual \(readingTop(first) - firstAnswer.frame.minY)")
        XCTAssertEqual(firstAnswer.frame.minX, leftA, accuracy: 2, "Paging must preserve horizontal text alignment")
        first.swipeLeft()
        let restoredB = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs((readingTop(second) - secondAnswer.frame.minY) - offsetB) < 25 && abs(secondAnswer.frame.minX - leftB) < 2
        }, object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [restoredB], timeout: 5), .completed, "Expected \(offsetB), actual \(readingTop(second) - secondAnswer.frame.minY)")
        XCTAssertEqual(secondAnswer.frame.minX, leftB, accuracy: 2, "Paging must preserve horizontal text alignment")
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
        start.press(forDuration: 0.8, thenDragTo: end)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["取消"].exists)
        XCTAssertTrue(alert.buttons["删除"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        alert.buttons["取消"].tap()
        XCTAssertEqual(row.label, originalLabel)
        start.press(forDuration: 0.8, thenDragTo: end)
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
        XCTAssertLessThan(scroll.frame.minY, tab.frame.minY, "The reader must extend behind the glass bar")
        scroll.swipeUp()
        XCTAssertTrue(tab.waitForNonExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(scroll.frame.height + 1, height)
        // Native paging may inset the frame at rounded screen corners. Reading must
        // extend into the status-bar band and reach the bottom edge.
        let fullScreen = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            scroll.frame.minY < app.frame.minY + app.frame.height * 0.05 && scroll.frame.maxY >= app.frame.maxY - 1
        }, object: scroll)
        XCTAssertEqual(XCTWaiter.wait(for: [fullScreen], timeout: 5), .completed, "Reading viewport: \(scroll.frame); screen: \(app.frame)")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
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
        XCTAssertLessThan(scroll.frame.minY, tab.frame.minY, "The reader must extend behind the glass bar")
        scroll.swipeUp()
        XCTAssertTrue(tab.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.textFields["prompt-field"].exists)
        XCTAssertGreaterThanOrEqual(scroll.frame.height + 1, originalHeight)
        // Native paging may inset the frame at rounded screen corners. Reading must
        // extend into the status-bar band and reach the bottom edge.
        let fullScreen = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            scroll.frame.minY < app.frame.minY + app.frame.height * 0.05 && scroll.frame.maxY >= app.frame.maxY - 1
        }, object: scroll)
        XCTAssertEqual(XCTWaiter.wait(for: [fullScreen], timeout: 5), .completed, "Reading viewport: \(scroll.frame); screen: \(app.frame)")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        scroll.swipeUp()
        scroll.swipeDown()
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["prompt-field"].exists)
        Thread.sleep(forTimeInterval: 0.5)
        let glassScreenshot = XCTAttachment(screenshot: app.screenshot()); glassScreenshot.lifetime = .keepAlways; add(glassScreenshot)
        XCTAssertGreaterThan(scroll.frame.maxY, app.textFields["prompt-field"].frame.maxY, "The reader must extend behind the input surroundings")
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
