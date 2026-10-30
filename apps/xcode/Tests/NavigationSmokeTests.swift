import Foundation
import XCTest

@MainActor
final class NavigationSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFourDestinationsAreReachable() throws {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["暂无明细"].waitForExistence(timeout: 15))
        attachScreenshot(app, name: "01-details")
        navigate(app, destination: "bills", title: "账单")
        XCTAssertTrue(app.staticTexts["暂无账单"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "02-bills")
        navigate(app, destination: "books", title: "账本")
        XCTAssertTrue(app.buttons["book.add"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "03-books")
        navigate(app, destination: "settings", title: "我的")
        XCTAssertTrue(app.otherElements["settings.back-tap-guide"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings.open-shortcuts"].exists)
        XCTAssertTrue(app.staticTexts["settings.sync-status"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "04-settings")
        navigate(app, destination: "details", title: "明细")
        XCTAssertTrue(app.staticTexts["暂无明细"].waitForExistence(timeout: 10))
        #if os(iOS)
        app.buttons["entry.add"].tap()
        XCTAssertTrue(app.buttons["editor.cancel"].waitForExistence(timeout: 10))
        app.buttons["keypad.date"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "editor.date").firstMatch.waitForExistence(timeout: 10))
        app.buttons["确定"].tap()
        app.buttons["editor.book"].tap()
        let bookOption = app.buttons["editor.book.option.A20E127A-36F6-401A-A6E3-000000000001"]
        XCTAssertTrue(bookOption.waitForExistence(timeout: 5))
        bookOption.tap()
        app.buttons["editor.cancel"].tap()
        XCTAssertTrue(app.staticTexts["暂无明细"].waitForExistence(timeout: 10))
        #endif
    }

    #if os(iOS)
    func testMonthPickerBrowsesYearsAndUpdatesBothViews() throws {
        let app = makeApplication()
        app.launch()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let currentMonth = calendar.component(.month, from: Date())
        let monthTitle = app.buttons["month.title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 15))
        monthTitle.tap()

        XCTAssertTrue(app.buttons["month-picker.year-toggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["month-picker.close"].exists)
        XCTAssertTrue(app.buttons["month-picker.month.\(currentMonth)"].isSelected)
        attachScreenshot(app, name: "month-picker-months")

        let monthGrid = app.descendants(matching: .any)["month-picker.month-grid"].firstMatch
        XCTAssertTrue(monthGrid.waitForExistence(timeout: 5))
        let diagonalStart = monthGrid.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.35))
        let diagonalEnd = monthGrid.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.55))
        diagonalStart.press(forDuration: 0.1, thenDragTo: diagonalEnd)
        XCTAssertTrue(app.buttons["month-picker.close"].exists)
        XCTAssertTrue(app.buttons["month-picker.year-toggle"].label.contains(String(currentYear + 1)))
        XCTAssertFalse(app.buttons["month-picker.month.\(currentMonth)"].isSelected)
        attachScreenshot(app, name: "month-picker-other-year-no-highlight")
        monthGrid.swipeRight()
        XCTAssertTrue(app.buttons["month-picker.year-toggle"].label.contains(String(currentYear)))
        XCTAssertTrue(app.buttons["month-picker.month.\(currentMonth)"].isSelected)
        monthGrid.swipeLeft()

        app.buttons["month-picker.current"].tap()
        XCTAssertTrue(app.buttons["month-picker.year-toggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["month-picker.year-toggle"].label.contains(String(currentYear)))
        XCTAssertTrue(app.buttons["month-picker.month.\(currentMonth)"].isSelected)

        app.buttons["month-picker.year-toggle"].tap()
        XCTAssertTrue(app.staticTexts["month-picker.year-range"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "month-picker-years")
        app.buttons["month-picker.back-to-months"].tap()
        XCTAssertTrue(app.buttons["month-picker.year-toggle"].waitForExistence(timeout: 5))
        app.buttons["month-picker.year-toggle"].tap()

        let previousPageLastYear = currentYear - currentYear % 10 - 1
        app.buttons["month-picker.range.previous"].tap()
        let targetYear = app.buttons["month-picker.year.\(previousPageLastYear)"]
        XCTAssertTrue(targetYear.waitForExistence(timeout: 5))
        targetYear.tap()
        XCTAssertTrue(app.buttons["month-picker.month.1"].waitForExistence(timeout: 5))
        app.buttons["month-picker.month.1"].tap()

        XCTAssertTrue(monthTitle.waitForExistence(timeout: 5))
        XCTAssertTrue((monthTitle.value as? String)?.contains(String(previousPageLastYear)) == true)
        XCTAssertTrue((monthTitle.value as? String)?.contains("1月") == true)

        navigate(app, destination: "bills", title: "账单")
        let billMonthTitle = app.buttons["month.title"]
        XCTAssertTrue(billMonthTitle.waitForExistence(timeout: 5))
        XCTAssertTrue((billMonthTitle.value as? String)?.contains(String(previousPageLastYear)) == true)
        XCTAssertTrue((billMonthTitle.value as? String)?.contains("1月") == true)
        billMonthTitle.tap()
        XCTAssertTrue(app.buttons["month-picker.close"].waitForExistence(timeout: 5))
        app.buttons["month-picker.close"].tap()
        XCTAssertFalse(app.buttons["month-picker.close"].waitForExistence(timeout: 1))
    }

    func testScreenshotCategoriesAreSelectableIncludingLastRowAndIncome() throws {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.buttons["entry.add"].waitForExistence(timeout: 15))
        app.buttons["entry.add"].tap()
        XCTAssertTrue(app.buttons["editor.kind.expense"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "categories-expense-top")
        let expenses: [(Int, String)] = [
            (101, "餐饮"), (102, "交通"), (103, "购物"), (106, "宠物"),
            (107, "住房"), (108, "零食"), (109, "旅行"), (110, "通讯"),
            (111, "医疗"), (112, "Pos"), (105, "其它"), (113, "礼金"),
            (114, "运动"), (104, "日用")
        ]
        for (number, name) in expenses {
            let category = revealCategory(app, number: number)
            XCTAssertEqual(category.label, name)
            category.tap()
            XCTAssertTrue(category.isSelected, "分类未选中：\(name)")
        }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "editor.category.", "设置")).firstMatch.exists)
        attachScreenshot(app, name: "categories-expense-last-row")
        app.buttons["editor.kind.income"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editor.category.")).count, 3)
        for (number, name) in [(201, "工资"), (202, "奖金"), (203, "其他收入")] {
            let category = revealCategory(app, number: number)
            XCTAssertEqual(category.label, name)
            category.tap()
            XCTAssertTrue(category.isSelected)
        }
        attachScreenshot(app, name: "categories-income")
        app.buttons["editor.cancel"].tap()
        XCTAssertTrue(app.staticTexts["暂无明细"].waitForExistence(timeout: 10))
    }

    func testScreenshotShortcutProposalOpensPrefilledConfirmationAndSaves() throws {
        let app = makeApplication()
        app.launchArguments.append("--ui-test-screenshot-proposal")
        app.launch()

        XCTAssertTrue(app.staticTexts["editor.screenshot-confirmation"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["editor.amount"].label.contains("55.00"))
        XCTAssertEqual(app.textFields["editor.note"].value as? String, "星巴克咖啡")
        XCTAssertTrue(app.buttons["editor.kind.expense"].isSelected)
        XCTAssertTrue(app.buttons["editor.category.A20E127A-36F6-401A-A6E3-000000000101"].isSelected)
        attachScreenshot(app, name: "screenshot-shortcut-confirmation")

        app.buttons["editor.save"].tap()
        let saved = entryButton(app, note: "星巴克咖啡")
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue(saved.label.contains("餐饮"))
        XCTAssertTrue(saved.label.contains("55.00"))
    }


    func testNewCategoriesPersistAcrossRelaunchIncludingLastRow() throws {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.buttons["entry.add"].waitForExistence(timeout: 15))
        for (number, name, amount, note) in [(114, "运动", "12.34", "末行运动分类验收"), (106, "宠物", "6.78", "宠物分类验收")] {
            app.buttons["entry.add"].tap()
            XCTAssertTrue(app.buttons["editor.kind.expense"].waitForExistence(timeout: 10))
            revealCategory(app, number: number).tap()
            typeAmount(app, expression: amount)
            app.textFields["editor.note"].tap()
            app.textFields["editor.note"].typeText(note)
            app.buttons["editor.keypad-return"].tap()
            app.buttons["editor.save"].tap()
            let row = entryButton(app, note: note)
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            XCTAssertTrue(row.label.contains(name))
        }
        app.terminate()
        app.launch()
        for (name, amount, note) in [("运动", "12.34", "末行运动分类验收"), ("宠物", "6.78", "宠物分类验收")] {
            let row = entryButton(app, note: note)
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            XCTAssertTrue(row.label.contains(name))
            row.tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["detail.amount"].label.contains(amount))
            XCTAssertTrue(app.staticTexts["detail.note"].label.contains(note))
            attachScreenshot(app, name: "category-persisted-\(name)")
            app.buttons["detail.close"].tap()
        }
    }

    private func revealCategory(_ app: XCUIApplication, number: Int) -> XCUIElement {
        let category = app.buttons[String(format: "editor.category.A20E127A-36F6-401A-A6E3-%012d", number)]
        let scroll = app.scrollViews["editor.categories"]
        for _ in 0..<4 {
            if category.exists && category.isHittable && category.frame.minY >= scroll.frame.minY && category.frame.maxY <= scroll.frame.maxY { return category }
            scroll.swipeUp()
        }
        XCTAssertTrue(category.isHittable, "分类不可达：\(number)")
        XCTAssertLessThanOrEqual(category.frame.maxY, scroll.frame.maxY, "分类被键盘遮挡：\(number)")
        return category
    }

    func testEntryCreateEditRelaunchAndDelete() throws {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.buttons["entry.add"].waitForExistence(timeout: 15))
        navigate(app, destination: "bills", title: "账单")
        app.buttons["entry.add"].tap()
        XCTAssertTrue(app.buttons["keypad.1"].waitForExistence(timeout: 10))
        typeAmount(app, expression: "1.234")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts["editor.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.amount"].label.contains("1.234"))
        typeAmount(app, expression: "12.34+7.66-5", clearing: 5)
        attachScreenshot(app, name: "05-editor-calculator")
        app.textFields["editor.note"].tap()
        app.textFields["editor.note"].typeText("UI测试早餐")
        app.buttons["editor.keypad-return"].tap()
        app.buttons["editor.save"].tap()
        let created = entryButton(app, note: "UI测试早餐")
        XCTAssertTrue(created.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["summary.expense"].label.contains("15.00"))
        attachScreenshot(app, name: "entry-created")
        navigate(app, destination: "details", title: "明细")
        let today = Calendar.current.component(.day, from: Date())
        let todayButton = app.buttons["calendar.day.\(today)"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 10))
        todayButton.tap()
        XCTAssertTrue(entryButton(app, note: "UI测试早餐").exists)
        attachScreenshot(app, name: "06-calendar-selected-day")
        let other = today == 1 ? 2 : 1
        app.buttons["calendar.day.\(other)"].tap()
        XCTAssertTrue(app.staticTexts["暂无明细"].waitForExistence(timeout: 5))
        app.buttons["calendar.clear-selection"].tap()
        app.buttons["month.previous"].tap()
        XCTAssertTrue(app.staticTexts["暂无明细"].waitForExistence(timeout: 5))
        app.buttons["month.next"].tap()
        XCTAssertTrue(entryButton(app, note: "UI测试早餐").waitForExistence(timeout: 5))
        navigate(app, destination: "bills", title: "账单")
        created.tap()
        XCTAssertTrue(app.buttons["entry.edit"].waitForExistence(timeout: 10))
        app.buttons["entry.edit"].tap()
        XCTAssertTrue(app.buttons["keypad.2"].waitForExistence(timeout: 10))
        typeAmount(app, expression: "23.45", clearing: 5)
        clearAndType(app.textFields["editor.note"], text: "UI测试修改早餐")
        app.buttons["editor.keypad-return"].tap()
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts["detail.amount"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["detail.amount"].label.contains("23.45"))
        XCTAssertTrue(app.staticTexts["detail.note"].label.contains("UI测试修改早餐"))
        attachScreenshot(app, name: "entry-edited-detail")
        app.buttons["detail.close"].tap()

        app.terminate()
        app.launch()
        navigate(app, destination: "bills", title: "账单")
        let persisted = entryButton(app, note: "UI测试修改早餐")
        XCTAssertTrue(persisted.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["summary.expense"].label.contains("23.45"))
        attachScreenshot(app, name: "entry-persisted-after-relaunch")
        persisted.tap()
        XCTAssertTrue(app.buttons["entry.delete"].waitForExistence(timeout: 10))
        app.buttons["entry.delete"].tap()
        let confirmDelete = app.buttons.matching(identifier: "entry.delete.confirm").firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertTrue(app.staticTexts["暂无账单"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["暂无明细"].waitForExistence(timeout: 15))
        attachScreenshot(app, name: "entry-deleted-after-relaunch")
    }

    func testBooksRenameIncomeAndSelectionScope() throws {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.buttons["entry.add"].waitForExistence(timeout: 15))
        navigate(app, destination: "books", title: "账本")
        app.buttons["book.add"].tap()
        XCTAssertTrue(app.textFields["book-editor.name"].waitForExistence(timeout: 10))
        app.textFields["book-editor.name"].tap()
        app.textFields["book-editor.name"].typeText("UI验收账本")
        app.buttons["book-editor.save"].tap()
        let rename = app.buttons["重命名UI验收账本"]
        XCTAssertTrue(rename.waitForExistence(timeout: 10))
        rename.tap()
        XCTAssertTrue(app.textFields["book-editor.name"].waitForExistence(timeout: 10))
        clearAndType(app.textFields["book-editor.name"], text: "UI验收新账本")
        app.buttons["book-editor.save"].tap()
        XCTAssertTrue(app.buttons["UI验收新账本"].waitForExistence(timeout: 10))
        navigate(app, destination: "bills", title: "账单")
        XCTAssertTrue(app.buttons["ledger.book-picker"].label.contains("UI验收新账本"))
        app.buttons["entry.add"].tap()
        XCTAssertTrue(app.buttons["editor.kind.income"].waitForExistence(timeout: 10))
        app.buttons["editor.kind.income"].tap()
        typeAmount(app, expression: "28.88")
        app.textFields["editor.note"].tap()
        app.textFields["editor.note"].typeText("UI测试工资")
        app.buttons["editor.keypad-return"].tap()
        app.buttons["editor.save"].tap()
        XCTAssertTrue(entryButton(app, note: "UI测试工资").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["summary.income"].label.contains("28.88"))
        navigate(app, destination: "details", title: "明细")
        XCTAssertTrue(entryButton(app, note: "UI测试工资").waitForExistence(timeout: 10))
        navigate(app, destination: "books", title: "账本")
        app.buttons["日常账本"].tap()
        navigate(app, destination: "bills", title: "账单")
        XCTAssertTrue(app.staticTexts["暂无账单"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["summary.income"].label.contains("0.00"))
        navigate(app, destination: "details", title: "明细")
        XCTAssertTrue(app.staticTexts["暂无明细"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "book-selection-scopes-entries")
    }

    func testStartupFailureOffersRetryWithoutMemoryFallback() throws {
        let app = makeApplication()
        app.launchArguments.append("--ui-test-fail-open-once")
        app.launch()
        XCTAssertTrue(app.staticTexts["startup.error"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["entry.add"].exists)
        app.buttons["startup.retry"].tap()
        XCTAssertTrue(app.buttons["entry.add"].waitForExistence(timeout: 15))
    }

    func testUpdateInstallationPreservesExistingFixture() throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let mode = environment["YOLO_LEDGER_UPDATE_TEST_MODE"],
            let storeID = environment["YOLO_LEDGER_UPDATE_TEST_STORE_ID"],
            UUID(uuidString: storeID) != nil
        else {
            throw XCTSkip("仅由覆盖安装的 seed / verify 两阶段测试启用")
        }

        let app = makeApplication(storeID: storeID)
        app.launch()
        XCTAssertTrue(app.buttons["entry.add"].waitForExistence(timeout: 15))
        let note = "覆盖安装保留验证"
        let fixture = entryButton(app, note: note)

        switch mode {
        case "seed":
            if !fixture.exists {
                app.buttons["entry.add"].tap()
                XCTAssertTrue(app.buttons["keypad.8"].waitForExistence(timeout: 10))
                typeAmount(app, expression: "88.66")
                app.textFields["editor.note"].tap()
                app.textFields["editor.note"].typeText(note)
                app.buttons["editor.keypad-return"].tap()
                app.buttons["editor.save"].tap()
            }
            XCTAssertTrue(fixture.waitForExistence(timeout: 10))
            app.terminate()
        case "verify":
            XCTAssertTrue(fixture.waitForExistence(timeout: 15), "覆盖安装后未找到升级前账目")
            XCTAssertTrue(app.staticTexts["summary.expense"].label.contains("88.66"))
            fixture.tap()
            XCTAssertTrue(app.staticTexts["detail.amount"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["detail.amount"].label.contains("88.66"))
            XCTAssertTrue(app.staticTexts["detail.note"].label.contains(note))
            attachScreenshot(app, name: "update-installation-preserved-entry")
        default:
            XCTFail("未知覆盖安装测试阶段：\(mode)")
        }
    }

    private func typeAmount(_ app: XCUIApplication, expression: String, clearing: Int = 0) {
        for _ in 0..<clearing { app.buttons["keypad.delete"].tap() }
        for character in expression { app.buttons["keypad.\(character)"].tap() }
    }

    private func entryButton(_ app: XCUIApplication, note: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "entry.row.", note)).firstMatch
    }

    private func clearAndType(_ field: XCUIElement, text: String) {
        field.tap()
        if let value = field.value as? String, value != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }
    #endif

    private func makeApplication() -> XCUIApplication {
        makeApplication(storeID: UUID().uuidString)
    }

    private func makeApplication(storeID: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", storeID]
        return app
    }

    private func navigate(_ app: XCUIApplication, destination: String, title: String) {
        #if os(macOS)
        let item = app.descendants(matching: .any).matching(identifier: "navigation.\(destination)").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.click()
        #else
        let item = app.buttons["navigation.\(destination)"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        #endif
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
