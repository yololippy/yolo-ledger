import Foundation

/// A strictly positive CNY amount represented exactly in fen, never as Double.
public struct LedgerAmount: Equatable, Hashable, Sendable {
    public let minorUnits: Int64

    public init(minorUnits: Int64) throws {
        guard minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
        self.minorUnits = minorUnits
    }

    /// Accepts ASCII digits with an optional one- or two-digit fractional part.
    /// Leading and trailing whitespace is ignored; signs, separators and exponents are rejected.
    public init(input: String) throws {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = input.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              !parts[0].isEmpty,
              parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              parts.count == 1 || (1...2).contains(parts[1].utf8.count)
        else { throw LedgerError.invalidAmount }

        var whole: Int64 = 0
        for byte in parts[0].utf8 {
            let (shifted, multiplyOverflow) = whole.multipliedReportingOverflow(by: 10)
            let (next, addOverflow) = shifted.addingReportingOverflow(Int64(byte - 48))
            guard !multiplyOverflow, !addOverflow else { throw LedgerError.amountOverflow }
            whole = next
        }
        let (base, overflow) = whole.multipliedReportingOverflow(by: 100)
        guard !overflow else { throw LedgerError.amountOverflow }

        var fraction: Int64 = 0
        if parts.count == 2 {
            for byte in parts[1].utf8 {
                fraction = fraction * 10 + Int64(byte - 48)
            }
            if parts[1].utf8.count == 1 { fraction *= 10 }
        }
        let (total, addOverflow) = base.addingReportingOverflow(fraction)
        guard !addOverflow else { throw LedgerError.amountOverflow }
        try self.init(minorUnits: total)
    }

    public var decimalString: String {
        Self.format(minorUnits: minorUnits)
    }

    /// Formats exact minor units, including zero and negative summary balances.
    public static func format(minorUnits: Int64) -> String {
        let magnitude = minorUnits.magnitude
        let fraction = magnitude % 100
        let sign = minorUnits < 0 ? "-" : ""
        let padding = fraction < 10 ? "0" : ""
        return "\(sign)\(magnitude / 100).\(padding)\(fraction)"
    }
}
