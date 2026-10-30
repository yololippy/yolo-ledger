import Foundation
import Testing
@testable import YoloLedgerCore

struct LedgerScreenshotRecognitionTests {
    @Test func recognizesPaymentAmountMerchantDateAndCategory() throws {
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 18)))
        let proposal = LedgerScreenshotParser.parse(lines: [
            .init(text: "支付成功", height: 0.03),
            .init(text: "星巴克咖啡", height: 0.04),
            .init(text: "实付金额", height: 0.025),
            .init(text: "¥ 55.00", height: 0.08),
            .init(text: "交易时间 2026-10-30 12:35:01"),
            .init(text: "订单号 202610301234567890"),
        ], now: now)

        #expect(proposal.amountMinorUnits == 5_500)
        #expect(proposal.merchant == "星巴克咖啡")
        #expect(proposal.kind == .expense)
        #expect(proposal.suggestedCategoryName == "餐饮")
        #expect(proposal.confidence == .high)
        #expect(Calendar.current.component(.hour, from: try #require(proposal.transactionDate)) == 12)
    }

    @Test func labeledMerchantAndPaymentBeatBalanceAndDiscount() {
        let proposal = LedgerScreenshotParser.parse(lines: [
            .init(text: "微信支付"),
            .init(text: "收款方：山野面馆"),
            .init(text: "订单金额 ¥36.00"),
            .init(text: "优惠 ¥6.00"),
            .init(text: "实付 ¥30.00"),
            .init(text: "零钱余额 128.50"),
        ])

        #expect(proposal.amountMinorUnits == 3_000)
        #expect(proposal.merchant == "山野面馆")
        #expect(proposal.suggestedCategoryName == "餐饮")
    }

    @Test func recognizesRefundAsIncome() {
        let proposal = LedgerScreenshotParser.parse(lines: [
            .init(text: "退款成功"),
            .init(text: "退款金额 ¥18.88", height: 0.06),
            .init(text: "淘宝订单"),
        ])

        #expect(proposal.amountMinorUnits == 1_888)
        #expect(proposal.kind == .income)
        #expect(proposal.suggestedCategoryName == "其他收入")
    }

    @Test func shoppingOrderRefundServicesRemainExpenseAndMerchantBecomesNote() {
        let proposal = LedgerScreenshotParser.parse(lines: [
            .init(text: "支付成功"),
            .init(text: "示例服饰旗舰店", height: 0.04),
            .init(text: "秋冬加绒长裤 ¥259"),
            .init(text: "极速退款"),
            .init(text: "店铺优惠 -¥40"),
            .init(text: "平台优惠 -¥73.81"),
            .init(text: "实付款 ¥145.19", height: 0.07),
            .init(text: "退货包运费"),
            .init(text: "订单号 202610301234567890"),
        ])

        #expect(proposal.amountMinorUnits == 14_519)
        #expect(proposal.kind == .expense)
        #expect(proposal.merchant == "示例服饰旗舰店")
        #expect(proposal.suggestedCategoryName == "购物")
    }

    @Test func storedValuePaymentBeatsZeroCashPaymentAndItemPrice() {
        let proposal = LedgerScreenshotParser.parse(lines: [
            .init(text: "交易成功"),
            .init(text: "天猫超市", height: 0.04),
            .init(text: "商品实付价 ¥27.55"),
            .init(text: "商品总价 ¥49.90"),
            .init(text: "店铺优惠 -¥12.90"),
            .init(text: "天猫超市卡 -¥27.55"),
            .init(text: "实付款 ¥0", height: 0.06),
        ])

        #expect(proposal.amountMinorUnits == 2_755)
        #expect(proposal.kind == .expense)
        #expect(proposal.merchant == "天猫超市")
        #expect(proposal.suggestedCategoryName == "购物")
    }

    @Test func doesNotTreatTimeOrOrderNumberAsAmount() {
        let proposal = LedgerScreenshotParser.parse(lines: [
            .init(text: "交易时间 14:30:22"),
            .init(text: "交易日期 2026-10-30"),
            .init(text: "订单号 202610301234567890"),
            .init(text: "支付成功"),
        ])

        #expect(proposal.amountMinorUnits == nil)
        #expect(proposal.confidence == .low)
    }

    @Test func recognizesIntegerAmountAfterLabelColon() {
        let proposal = LedgerScreenshotParser.parse(lines: [.init(text: "实付: 55")])
        #expect(proposal.amountMinorUnits == 5_500)
    }

    @Test func proposalRoundTripsForPendingShortcutStorage() throws {
        let proposal = LedgerScreenshotParser.parse(lines: [.init(text: "实付 ¥12.34")])
        let data = try JSONEncoder().encode(proposal)
        #expect(try JSONDecoder().decode(LedgerScreenshotProposal.self, from: data) == proposal)
    }
}
