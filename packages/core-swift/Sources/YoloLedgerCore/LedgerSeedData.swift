import Foundation

/// Expense names and order follow the user-provided Meow Ledger screenshot (2026-10-28).
/// Existing identifiers and income choices remain stable; legacy 日用 is retained at the end of expenses.
public enum LedgerSeedData {
    public static let defaultBook = LedgerBook(
        id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000001")!,
        name: "日常账本"
    )

    public static let books = [defaultBook]

    public static let categories: [LedgerCategory] = [
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000101")!, name: "餐饮", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000102")!, name: "交通", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000103")!, name: "购物", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000106")!, name: "宠物", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000107")!, name: "住房", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000108")!, name: "零食", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000109")!, name: "旅行", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000110")!, name: "通讯", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000111")!, name: "医疗", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000112")!, name: "Pos", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000105")!, name: "其它", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000113")!, name: "礼金", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000114")!, name: "运动", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000104")!, name: "日用", kind: .expense),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000201")!, name: "工资", kind: .income),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000202")!, name: "奖金", kind: .income),
        LedgerCategory(id: UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000203")!, name: "其他收入", kind: .income),
    ]
}
