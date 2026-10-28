import Foundation

/// Evaluates decimal CNY amounts separated by binary + and - from left to right.
public enum LedgerAmountExpression {
    /// Operands may be zero and may end in a decimal point (12. means 12.00).
    /// Signs, internal whitespace, other operators, and incomplete operands are rejected.
    /// Every operand and intermediate result must fit Int64 minor units; the final result must be positive.
    public static func evaluate(_ input: String) throws -> LedgerAmount {
        let expression = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { throw LedgerError.invalidAmountExpression }

        var total: Int64 = 0
        var operation: Character = "+"
        var start = expression.startIndex

        for index in expression.indices {
            let character = expression[index]
            guard character == "+" || character == "-" else { continue }
            let operand = try parseOperand(expression[start..<index])
            total = try apply(operation, to: total, operand: operand)
            operation = character
            start = expression.index(after: index)
        }

        let operand = try parseOperand(expression[start...])
        total = try apply(operation, to: total, operand: operand)
        return try LedgerAmount(minorUnits: total)
    }

    private static func parseOperand(_ token: Substring) throws -> Int64 {
        guard !token.isEmpty,
              token.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }),
              token.utf8.filter({ $0 == 46 }).count <= 1
        else { throw LedgerError.invalidAmountExpression }

        var number = String(token)
        if number.last == "." { number.removeLast() }
        do {
            return try LedgerAmount(input: number).minorUnits
        } catch LedgerError.nonPositiveAmount {
            // The token contains only unsigned digits and '.', so this means exactly zero.
            return 0
        } catch LedgerError.invalidAmount {
            throw LedgerError.invalidAmountExpression
        }
    }

    private static func apply(_ operation: Character, to total: Int64, operand: Int64) throws -> Int64 {
        let result = operation == "+"
            ? total.addingReportingOverflow(operand)
            : total.subtractingReportingOverflow(operand)
        guard !result.overflow else { throw LedgerError.amountOverflow }
        return result.partialValue
    }
}
