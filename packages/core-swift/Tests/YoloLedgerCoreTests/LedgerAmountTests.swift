import XCTest
import YoloLedgerCore

final class LedgerAmountTests: XCTestCase {
    func testDecimalInputsRemainExactInMinorUnits() throws {
        XCTAssertEqual(try LedgerAmount(input: "0.1").minorUnits, 10)
        XCTAssertEqual(try LedgerAmount(input: "0.2").minorUnits, 20)
        XCTAssertEqual(try LedgerAmount(input: "0012.30").minorUnits, 1230)
        XCTAssertEqual(try LedgerAmount(input: "  12.3\n").decimalString, "12.30")
        XCTAssertEqual(try LedgerAmount(input: "1").decimalString, "1.00")
        XCTAssertEqual(try LedgerAmount(input: "0.01").minorUnits, 1)
    }

    func testRejectsUnsupportedNumericFormsInsteadOfRoundingOrGuessing() {
        for input in ["", " ", ".5", "1.", "+1", "-1", "1.234", "1.000", "1,000", "1,23", "1e2", "NaN", "inf", "1.2.3", "1 2", "１２.３４", "١٢.٣٤"] {
            XCTAssertThrowsError(try LedgerAmount(input: input), input) { error in
                XCTAssertEqual(error as? LedgerError, .invalidAmount, input)
            }
        }
    }

    func testRejectsZeroAndNegativeMinorUnits() {
        for input in ["0", "0.00", "000.0"] {
            XCTAssertThrowsError(try LedgerAmount(input: input)) { error in
                XCTAssertEqual(error as? LedgerError, .nonPositiveAmount)
            }
        }
        for minorUnits: Int64 in [0, -1, .min] {
            XCTAssertThrowsError(try LedgerAmount(minorUnits: minorUnits)) { error in
                XCTAssertEqual(error as? LedgerError, .nonPositiveAmount)
            }
        }
    }

    func testMaximumAmountRoundTripsWithoutFloatingPoint() throws {
        let maximum = try LedgerAmount(input: "92233720368547758.07")
        XCTAssertEqual(maximum.minorUnits, Int64.max)
        XCTAssertEqual(maximum.decimalString, "92233720368547758.07")
        XCTAssertEqual(try LedgerAmount(input: maximum.decimalString), maximum)
    }

    func testOverflowAtEachParsingBoundaryThrows() {
        for input in ["92233720368547758.08", "92233720368547759", "9223372036854775808", String(repeating: "9", count: 100)] {
            XCTAssertThrowsError(try LedgerAmount(input: input), input) { error in
                XCTAssertEqual(error as? LedgerError, .amountOverflow, input)
            }
        }
    }

    func testFormattingZeroAndNegativeBalancesHandlesInt64Minimum() {
        XCTAssertEqual(LedgerAmount.format(minorUnits: 0), "0.00")
        XCTAssertEqual(LedgerAmount.format(minorUnits: -1), "-0.01")
        XCTAssertEqual(LedgerAmount.format(minorUnits: -1234), "-12.34")
        XCTAssertEqual(LedgerAmount.format(minorUnits: .min), "-92233720368547758.08")
    }
}
