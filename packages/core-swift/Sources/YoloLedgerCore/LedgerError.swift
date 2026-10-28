import Foundation

/// Domain errors that callers can present without exposing a database implementation.
public enum LedgerError: Error, Equatable, Sendable, LocalizedError {
    case invalidAmount
    case invalidAmountExpression
    case nonPositiveAmount
    case amountOverflow
    case summaryOverflow
    case emptyName
    case invalidDate
    case invalidDateRange
    case bookNotFound(UUID)
    case categoryNotFound(UUID)
    case entryNotFound(UUID)
    case duplicateIdentifier(UUID)
    case categoryKindMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidAmount:
            "请输入金额，最多保留两位小数。"
        case .invalidAmountExpression:
            "请输入完整的金额加减式，每项最多保留两位小数。"
        case .nonPositiveAmount:
            "金额必须大于零。"
        case .amountOverflow:
            "金额超出可保存范围。"
        case .summaryOverflow:
            "汇总金额超出可计算范围。"
        case .emptyName:
            "名称不能为空。"
        case .invalidDate:
            "记账日期无效。"
        case .invalidDateRange:
            "日期范围无效。"
        case .bookNotFound:
            "账本不存在，请重新选择。"
        case .categoryNotFound:
            "分类不存在，请重新选择。"
        case .entryNotFound:
            "账目不存在，可能已被删除。"
        case .duplicateIdentifier:
            "这条数据已经存在，请刷新后重试。"
        case .categoryKindMismatch:
            "分类与收入或支出类型不一致，请重新选择。"
        }
    }
}
