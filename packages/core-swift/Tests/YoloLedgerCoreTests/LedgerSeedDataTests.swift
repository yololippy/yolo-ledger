import Foundation
import XCTest
import YoloLedgerCore

final class LedgerSeedDataTests: XCTestCase {
    private func id(_ suffix: String) -> UUID {
        UUID(uuidString: "A20E127A-36F6-401A-A6E3-" + suffix)!
    }

    func testExpenseOrderMatchesProvidedScreenshotAndKeepsDailyUseLast() {
        let expenses = LedgerSeedData.categories.filter { $0.kind == .expense }
        XCTAssertEqual(expenses.map(\.name), [
            "餐饮", "交通", "购物", "宠物", "住房", "零食", "旅行",
            "通讯", "医疗", "Pos", "其它", "礼金", "运动", "日用",
        ])
        XCTAssertFalse(LedgerSeedData.categories.contains { $0.name == "设置" })
    }

    func testExistingExpenseIdentifiersArePreservedIncludingRenamedOther() throws {
        let existing: [(String, String)] = [
            ("000000000101", "餐饮"),
            ("000000000102", "交通"),
            ("000000000103", "购物"),
            ("000000000104", "日用"),
            ("000000000105", "其它"),
        ]
        for (suffix, name) in existing {
            let category = try XCTUnwrap(LedgerSeedData.categories.first { $0.id == id(suffix) })
            XCTAssertEqual(category.name, name)
            XCTAssertEqual(category.kind, .expense)
        }
        XCTAssertFalse(LedgerSeedData.categories.contains { $0.name == "其他支出" })
    }

    func testNewExpenseIdentifiersMatchStorageUpgradeContract() throws {
        let added: [(String, String)] = [
            ("000000000106", "宠物"),
            ("000000000107", "住房"),
            ("000000000108", "零食"),
            ("000000000109", "旅行"),
            ("000000000110", "通讯"),
            ("000000000111", "医疗"),
            ("000000000112", "Pos"),
            ("000000000113", "礼金"),
            ("000000000114", "运动"),
        ]
        for (suffix, name) in added {
            let category = try XCTUnwrap(LedgerSeedData.categories.first { $0.id == id(suffix) })
            XCTAssertEqual(category.name, name)
            XCTAssertEqual(category.kind, .expense)
        }
    }

    func testIncomeNamesOrderAndIdentifiersRemainUnchanged() {
        let incomes = LedgerSeedData.categories.filter { $0.kind == .income }
        XCTAssertEqual(incomes, [
            LedgerCategory(id: id("000000000201"), name: "工资", kind: .income),
            LedgerCategory(id: id("000000000202"), name: "奖金", kind: .income),
            LedgerCategory(id: id("000000000203"), name: "其他收入", kind: .income),
        ])
    }
}
