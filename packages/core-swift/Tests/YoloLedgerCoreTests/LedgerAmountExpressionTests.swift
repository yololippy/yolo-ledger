import XCTest
import YoloLedgerCore

final class LedgerAmountExpressionTests: XCTestCase {
    func testSingleAmountAndDecimalAdditionRemainExact() throws {
        XCTAssertEqual(try LedgerAmountExpression.evaluate("12.34").minorUnits, 1234)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("0.1+0.2").minorUnits, 30)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("00012.3+0.04").decimalString, "12.34")
        XCTAssertEqual(try LedgerAmountExpression.evaluate("0.01+0.02+0.03").minorUnits, 6)
    }

    func testMixedAdditionAndSubtractionEvaluateFromLeftToRight() throws {
        XCTAssertEqual(try LedgerAmountExpression.evaluate("10-3-2").decimalString, "5.00")
        XCTAssertEqual(try LedgerAmountExpression.evaluate("10+3-2+0.25").minorUnits, 1125)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("12.50+3-1.25").minorUnits, 1425)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("9-8+7-6+5-4+3-2+1").minorUnits, 500)
    }

    func testZeroOperandsAndNegativeIntermediateAmountsAreAllowed() throws {
        XCTAssertEqual(try LedgerAmountExpression.evaluate("0+12.50-0").minorUnits, 1250)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("0.00+0.01").minorUnits, 1)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("1-3+5").minorUnits, 300)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("0-1+2").minorUnits, 100)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("1-1+0.01").minorUnits, 1)
    }

    func testDecimalPointCanCompleteAnOperandAsWholeYuan() throws {
        XCTAssertEqual(try LedgerAmountExpression.evaluate("12.").decimalString, "12.00")
        XCTAssertEqual(try LedgerAmountExpression.evaluate("12.+3.").minorUnits, 1500)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("0.+1.25").minorUnits, 125)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("12.30-2.").minorUnits, 1030)
    }

    func testOnlyOuterWhitespaceIsIgnored() throws {
        XCTAssertEqual(try LedgerAmountExpression.evaluate(" \n12.50+3-1\t ").minorUnits, 1450)
        for input in ["12 +3", "12+ 3", "12\t+3", "12+3\n-1", "1 2+3"] {
            XCTAssertThrowsError(try LedgerAmountExpression.evaluate(input), input) { error in
                XCTAssertEqual(error as? LedgerError, .invalidAmountExpression, input)
            }
        }
    }

    func testExtraTrailingDecimalPointIsRejectedBeforeNormalization() {
        for input in ["1.2.", "12.34.", "1+0.0.", "1.2.+3", "0.00.+1", "12..+1", "1.234."] {
            XCTAssertThrowsError(try LedgerAmountExpression.evaluate(input), input) { error in
                XCTAssertEqual(error as? LedgerError, .invalidAmountExpression, input)
            }
        }
    }

    func testEmptyIncompleteAndUnaryExpressionsAreRejected() {
        for input in ["", " \n", "+1", "-1", "1+", "1-", "1++2", "1+-2", "1--2", "1-+2", "++1", "1+.", ".5+1", "1+.5", "1..+2", "."] {
            XCTAssertThrowsError(try LedgerAmountExpression.evaluate(input), input) { error in
                XCTAssertEqual(error as? LedgerError, .invalidAmountExpression, input)
            }
        }
    }

    func testUnsupportedCharactersAndExtraDecimalPlacesAreRejected() {
        for input in ["1*2", "1/2", "(1+2)", "1e2+1", "1,000+1", "1+NaN", "1+inf", "１２+1", "1−2+3", "1＋2", "¥12+1", "1.001+1", "1+2.000", "1.234-0.234", "1+2.3.4"] {
            XCTAssertThrowsError(try LedgerAmountExpression.evaluate(input), input) { error in
                XCTAssertEqual(error as? LedgerError, .invalidAmountExpression, input)
            }
        }
    }

    func testFinalZeroOrNegativeAmountIsRejected() {
        for input in ["0", "0.", "0+0", "1-1", "1-2", "0-0.01", "12.34-12.35"] {
            XCTAssertThrowsError(try LedgerAmountExpression.evaluate(input), input) { error in
                XCTAssertEqual(error as? LedgerError, .nonPositiveAmount, input)
            }
        }
    }

    func testOversizedOperandsAreRejectedEvenWhenLaterTermsCouldCancelThem() {
        for input in ["92233720368547758.08", "92233720368547759.+1", "1+92233720368547758.08", "92233720368547758.08-92233720368547758.08+1", String(repeating: "9", count: 100) + "+1"] {
            XCTAssertThrowsError(try LedgerAmountExpression.evaluate(input), input) { error in
                XCTAssertEqual(error as? LedgerError, .amountOverflow, input)
            }
        }
    }

    func testIntermediateArithmeticOverflowIsRejectedBeforeLaterCancellation() {
        for input in [
            "92233720368547758.07+0.01-0.01",
            "0-92233720368547758.07-0.02+92233720368547758.07",
            "92233720368547758.07+92233720368547758.07",
        ] {
            XCTAssertThrowsError(try LedgerAmountExpression.evaluate(input), input) { error in
                XCTAssertEqual(error as? LedgerError, .amountOverflow, input)
            }
        }
    }

    func testInt64BoundaryIntermediatesRecoverWithoutNegationOverflow() throws {
        XCTAssertEqual(try LedgerAmountExpression.evaluate("92233720368547758.07+0").minorUnits, .max)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("0-92233720368547758.07-0.01+92233720368547758.07+0.02").minorUnits, 1)
        XCTAssertEqual(try LedgerAmountExpression.evaluate("92233720368547758.07-92233720368547758.07+0.01").minorUnits, 1)
    }
}
