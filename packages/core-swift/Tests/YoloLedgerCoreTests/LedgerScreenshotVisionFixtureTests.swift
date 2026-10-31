import Foundation
import Testing
import Vision
@testable import YoloLedgerCore

@Suite(.serialized)
struct LedgerScreenshotVisionFixtureTests {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }()

    @Test func didiRideOriginalImageReturnsMatchingProposal() throws {
        let result = try recognize("didi-ride-1710")

        #expect(result.amountMinorUnits == 1_710)
        #expect(result.kind == .expense)
        #expect(result.suggestedCategoryName == "交通")
        #expect(result.merchant == "滴滴顺风车")
        let date = try #require(result.transactionDate)
        #expect(calendar.component(.year, from: date) == 2026)
        #expect(calendar.component(.month, from: date) == 10)
        #expect(calendar.component(.day, from: date) == 31)
        #expect(calendar.component(.hour, from: date) == 8)
        #expect(calendar.component(.minute, from: date) == 5)
    }

    @Test func tmallOriginalImageReturnsMatchingProposal() throws {
        let result = try recognize("tmall-supermarket-2755")

        #expect(result.amountMinorUnits == 2_755)
        #expect(result.kind == .expense)
        #expect(result.suggestedCategoryName == "购物")
        #expect(result.merchant == "天猫超市")
    }

    @Test func dickiesOriginalImageReturnsMatchingProposal() throws {
        let result = try recognize("dickies-order-14519")

        #expect(result.amountMinorUnits == 14_519)
        #expect(result.kind == .expense)
        #expect(result.suggestedCategoryName == "购物")
        #expect(result.merchant == "Dickies简约旗舰店")
    }

    @Test func aikangOriginalImageReturnsMatchingProposal() throws {
        let result = try recognize("aikang-health-15700")

        #expect(result.amountMinorUnits == 15_700)
        #expect(result.kind == .expense)
        #expect(result.suggestedCategoryName == "医疗")
        #expect(result.merchant == "天津爱康互联网信息服务有限公司")
        let date = try #require(result.transactionDate)
        #expect(calendar.component(.year, from: date) == 2026)
        #expect(calendar.component(.month, from: date) == 10)
        #expect(calendar.component(.day, from: date) == 31)
        #expect(calendar.component(.hour, from: date) == 8)
        #expect(calendar.component(.minute, from: date) == 27)
        #expect(calendar.component(.second, from: date) == 53)
    }

    @Test func internetCafeOriginalImageReturnsMatchingProposal() throws {
        let result = try recognize("internet-cafe-3922")

        #expect(result.amountMinorUnits == 3_922)
        #expect(result.kind == .expense)
        #expect(result.suggestedCategoryName == "其它")
        #expect(result.merchant == "哆哆网咖")
        let date = try #require(result.transactionDate)
        #expect(calendar.component(.year, from: date) == 2026)
        #expect(calendar.component(.month, from: date) == 10)
        #expect(calendar.component(.day, from: date) == 26)
        #expect(calendar.component(.hour, from: date) == 11)
        #expect(calendar.component(.minute, from: date) == 1)
        #expect(calendar.component(.second, from: date) == 44)
    }

    @Test func jdOrderOriginalImageReturnsMatchingProposal() throws {
        let result = try recognize("jd-north-face-265862")

        #expect(result.amountMinorUnits == 265_862)
        #expect(result.kind == .expense)
        #expect(result.suggestedCategoryName == "购物")
        #expect(result.merchant == "北面(The North Face)")
        let date = try #require(result.transactionDate)
        #expect(calendar.component(.year, from: date) == 2026)
        #expect(calendar.component(.month, from: date) == 10)
        #expect(calendar.component(.day, from: date) == 25)
        #expect(calendar.component(.hour, from: date) == 23)
        #expect(calendar.component(.minute, from: date) == 38)
        #expect(calendar.component(.second, from: date) == 49)
    }

    @Test func rideHailingOriginalImageReturnsMatchingProposal() throws {
        let result = try recognize("ride-hailing-3560")

        #expect(result.amountMinorUnits == 3_560)
        #expect(result.kind == .expense)
        #expect(result.suggestedCategoryName == "交通")
        #expect(result.merchant == "滴滴出行")
        #expect(result.transactionDate == nil)
    }

    private func recognize(_ resourceName: String) throws -> LedgerScreenshotProposal {
        let url = try #require(Bundle.module.url(
            forResource: resourceName,
            withExtension: "jpg",
            subdirectory: "Fixtures"
        ))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.009
        try VNImageRequestHandler(url: url).perform([request])

        let lines = (request.results ?? [])
            .sorted { left, right in
                if abs(left.boundingBox.maxY - right.boundingBox.maxY) > 0.01 {
                    return left.boundingBox.maxY > right.boundingBox.maxY
                }
                return left.boundingBox.minX < right.boundingBox.minX
            }
            .compactMap { observation -> LedgerRecognizedTextLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return LedgerRecognizedTextLine(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    height: observation.boundingBox.height
                )
            }
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 10,
            day: 31,
            hour: 8
        )))
        return LedgerScreenshotParser.parse(lines: lines, now: now, calendar: calendar)
    }
}
