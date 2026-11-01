import Foundation

public enum LedgerScreenshotConfidence: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct LedgerRecognizedTextLine: Equatable, Sendable {
    public let text: String
    public let confidence: Float
    public let height: Double

    public init(text: String, confidence: Float = 1, height: Double = 0) {
        self.text = text
        self.confidence = confidence
        self.height = height
    }
}

/// A local OCR result waiting for the user to confirm in the entry editor.
public struct LedgerScreenshotProposal: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let amountMinorUnits: Int64?
    public let merchant: String?
    public let transactionDate: Date?
    public let kind: LedgerEntryKind
    public let suggestedCategoryName: String?
    public let recognizedText: String
    public let confidence: LedgerScreenshotConfidence
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        amountMinorUnits: Int64?,
        merchant: String?,
        transactionDate: Date?,
        kind: LedgerEntryKind,
        suggestedCategoryName: String?,
        recognizedText: String,
        confidence: LedgerScreenshotConfidence,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amountMinorUnits = amountMinorUnits
        self.merchant = merchant
        self.transactionDate = transactionDate
        self.kind = kind
        self.suggestedCategoryName = suggestedCategoryName
        self.recognizedText = recognizedText
        self.confidence = confidence
        self.createdAt = createdAt
    }

    public var amount: LedgerAmount? {
        guard let amountMinorUnits else { return nil }
        return try? LedgerAmount(minorUnits: amountMinorUnits)
    }
}

public enum LedgerScreenshotParser {
    private struct AmountCandidate {
        let minorUnits: Int64
        let lineIndex: Int
        let score: Double
    }

    private struct AmountToken {
        let value: String
        let hasAmountMarker: Bool
        let localContext: String
    }

    private struct MerchantCandidate {
        let value: String
        let lineIndex: Int
        let score: Double
    }

    private struct MerchantContextRule {
        let merchant: String
        /// Every group must match; alternatives inside one group are OR-ed.
        let requiredKeywordGroups: [[String]]
    }

    private struct CategoryRule {
        let category: String
        let keywords: [String]
    }

    private static let amountKeywords = [
        "实付", "支付金额", "付款金额", "交易金额", "订单金额", "合计", "金额", "退款金额", "到账金额"
    ]
    private static let finalAmountKeywords = ["实付", "支付金额", "付款金额", "退款金额", "到账金额"]
    private static let summaryAmountKeywords = ["实付款", "实际付款", "实际支付", "付款总额"]
    private static let storedValuePaymentKeywords = ["超市卡", "礼品卡", "储值卡", "购物卡"]
    private static let secondaryAmountKeywords = ["支付成功", "付款成功", "交易成功", "退款成功", "已支付", "已收款"]
    private static let distractingAmountKeywords = [
        "优惠", "折扣", "红包", "积分", "余额", "手续费", "原价", "剩余",
        "奖励", "返现", "优惠券", "券包"
    ]
    private static let nonMerchantKeywords = [
        "支付成功", "付款成功", "交易成功", "退款成功", "账单详情", "交易详情", "订单详情", "收支明细",
        "支付方式", "交易时间", "付款时间", "订单号", "交易单号", "商户单号", "当前状态", "微信支付", "支付宝",
        "支付优惠", "店铺优惠", "平台优惠", "价格明细", "商品总价", "实付款", "实付价", "优惠解析",
        "确认收货", "查看物流", "申请售后", "加入购物车", "自动确认", "收货地址", "已签收", "退款", "退货",
        "大促", "价保", "粉丝", "上新", "客服", "复制", "超市卡", "礼品卡", "储值卡", "银行卡", "信用卡"
    ]
    private static let merchantSignalKeywords = [
        "旗舰店", "专卖店", "官方店", "便利店", "咖啡", "奶茶", "餐厅", "饭店", "面馆", "药房", "医院",
        "酒店", "民宿", "超市", "商店", "商城", "公司"
    ]
    private static let promotionalMerchantKeywords = [
        "摇一摇", "有优惠", "立减金", "领优惠", "领券", "优惠券", "活动详情", "活动专区", "福利中心",
        "奖励", "返现", "券包", "广告", "博主疯狂种草", "兑换惊喜好物"
    ]
    private static let merchantActionValues = [
        "查看", "立即查看", "立即购买", "完成", "关闭", "返回", "更多", "进店", "评价", "再次购买"
    ]
    private static let merchantLabels = [
        "商户全称", "收款方全称", "商户", "收款方", "付款给", "交易对象", "对方", "店铺"
    ]
    private static let emptyMerchantLabelValues = ["", "全称", "名称", "信息"]
    private static let merchantContextRules = [
        MerchantContextRule(
            merchant: "滴滴顺风车",
            requiredKeywordGroups: [["滴滴"], ["顺风车", "独享", "车主正在送你"]]
        ),
        MerchantContextRule(
            merchant: "滴滴出行",
            requiredKeywordGroups: [["滴滴"], ["车费", "行程", "接单"]]
        ),
        MerchantContextRule(
            merchant: "滴滴出行",
            requiredKeywordGroups: [["特惠快车", "呼叫返程"], ["联系司机", "费用说明", "全程"]]
        ),
    ]
    private static let confirmedMerchantCategoryRules = [
        CategoryRule(category: "餐饮", keywords: ["咔叽农场"]),
    ]
    private static let expenseCategoryRules = [
        CategoryRule(category: "餐饮", keywords: ["餐厅", "餐饮", "面馆", "饭店", "外卖", "美团", "饿了么", "咖啡", "奶茶", "麦当劳", "肯德基", "星巴克"]),
        CategoryRule(category: "交通", keywords: ["滴滴", "地铁", "公交", "出租", "铁路", "高铁", "加油", "停车"]),
        CategoryRule(category: "购物", keywords: ["淘宝", "天猫", "京东", "拼多多", "购物", "商城", "旗舰店", "专卖店", "官方店", "服饰"]),
        CategoryRule(category: "宠物", keywords: ["宠物", "猫粮", "狗粮"]),
        CategoryRule(category: "住房", keywords: ["房租", "物业", "水费", "电费", "燃气"]),
        CategoryRule(category: "零食", keywords: ["零食", "便利店"]),
        CategoryRule(category: "旅行", keywords: ["酒店", "机票", "旅行", "景区", "民宿"]),
        CategoryRule(category: "通讯", keywords: ["话费", "流量", "通信", "宽带"]),
        CategoryRule(category: "医疗", keywords: ["医院", "诊所", "药房", "医药", "爱康", "体检", "导检", "健康管理"]),
        CategoryRule(category: "礼金", keywords: ["礼金", "红包"]),
        CategoryRule(category: "运动", keywords: ["健身", "运动", "球馆"]),
        CategoryRule(category: "日用", keywords: ["超市", "日用", "百货"]),
    ]

    public static func parse(
        lines originalLines: [LedgerRecognizedTextLine],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LedgerScreenshotProposal {
        let lines = originalLines.map {
            LedgerRecognizedTextLine(
                text: normalize($0.text),
                confidence: $0.confidence,
                height: $0.height
            )
        }.filter { !$0.text.isEmpty }
        let joined = lines.map(\.text).joined(separator: "\n")
        let kind = inferredKind(from: joined)
        let candidate = bestAmount(in: lines)
        let merchant = inferredMerchant(from: lines, amountLineIndex: candidate?.lineIndex)
        let date = inferredDate(from: lines.map(\.text), now: now, calendar: calendar)
        let category = inferredCategory(from: joined, merchant: merchant, kind: kind)

        let confidence: LedgerScreenshotConfidence
        if let candidate, candidate.score >= 120, merchant != nil {
            confidence = .high
        } else if candidate != nil {
            confidence = .medium
        } else {
            confidence = .low
        }

        return LedgerScreenshotProposal(
            amountMinorUnits: candidate?.minorUnits,
            merchant: merchant,
            transactionDate: date,
            kind: kind,
            suggestedCategoryName: category,
            recognizedText: joined,
            confidence: confidence,
            createdAt: now
        )
    }

    private static func bestAmount(in lines: [LedgerRecognizedTextLine]) -> AmountCandidate? {
        let candidates = lines.enumerated().flatMap { index, line -> [AmountCandidate] in
            amountCandidates(in: line, at: index, allLines: lines)
        }.filter { $0.score >= 45 }

        // An explicit final-payment summary outranks product prices and discount rows. A zero
        // cash payment may still represent a stored-value-card purchase, in which case the card
        // debit is the amount that should be recorded.
        let summaryCandidates = candidates.filter {
            containsAny(lines[$0.lineIndex].text, summaryAmountKeywords)
        }
        if let summary = highestScoringAmount(in: summaryCandidates) {
            if summary.minorUnits == 0 {
                let storedValueCandidates = candidates.filter {
                    !containsAny(lines[$0.lineIndex].text, summaryAmountKeywords) &&
                    containsInLineOrNearby(
                        lines,
                        index: $0.lineIndex,
                        keywords: storedValuePaymentKeywords
                    )
                }
                if let storedValue = highestScoringAmount(in: storedValueCandidates) {
                    return storedValue
                }
            }
            return summary
        }
        return highestScoringAmount(in: candidates)
    }

    private static func amountCandidates(
        in line: LedgerRecognizedTextLine,
        at index: Int,
        allLines lines: [LedgerRecognizedTextLine]
    ) -> [AmountCandidate] {
        if containsAny(line.text, ["订单号", "交易单号", "商户单号", "流水号"]),
           !containsAny(line.text, amountKeywords) {
            return []
        }
        return amountTokens(in: line.text).compactMap { token in
            guard let minorUnits = parsedMinorUnitsAllowingZero(token.value) else { return nil }
            return AmountCandidate(
                minorUnits: minorUnits,
                lineIndex: index,
                score: amountScore(for: token, line: line, at: index, allLines: lines)
            )
        }
    }

    private static func amountScore(
        for token: AmountToken,
        line: LedgerRecognizedTextLine,
        at index: Int,
        allLines lines: [LedgerRecognizedTextLine]
    ) -> Double {
        var score = Double(line.confidence) * 20 + min(line.height * 160, 35)
        if token.hasAmountMarker { score += 45 }
        if token.value.contains(".") { score += 8 }

        // Local token context disambiguates rows containing both a discount and a final total.
        if containsAny(token.localContext, ["合计", "实付", "实际支付", "支付金额", "付款金额"]) {
            score += 90
        }
        if containsAny(token.localContext, ["共减", "共減", "共省", "立减", "立減"]) {
            score -= 120
        }

        if containsAny(line.text, summaryAmountKeywords) { score += 220 }
        else if containsAny(line.text, finalAmountKeywords) { score += 135 }
        else if containsAny(line.text, amountKeywords) { score += 75 }

        if containsInLineOrNearby(lines, index: index, keywords: storedValuePaymentKeywords) {
            score += 100
        }
        if containsAny(line.text, secondaryAmountKeywords) { score += 35 }
        if containsAny(line.text, distractingAmountKeywords) { score -= 60 }
        if containsAny(line.text, ["多", "少", "差额"]),
           containsAny(line.text, ["退款", "退回", "补收"]) {
            score -= 140
        }
        score += nearbyAmountEvidenceScore(lines, index: index)
        return score
    }

    private static func nearbyAmountEvidenceScore(
        _ lines: [LedgerRecognizedTextLine],
        index: Int
    ) -> Double {
        var score = 0.0
        for (lineIndex, line) in lines.enumerated() {
            let distance = abs(lineIndex - index)
            guard (1...2).contains(distance) else { continue }
            if containsAny(line.text, amountKeywords) {
                score += distance == 1 ? 58 : 28
            } else if containsAny(line.text, secondaryAmountKeywords) {
                score += distance == 1 ? 24 : 12
            }
        }
        return score
    }

    private static func highestScoringAmount(
        in candidates: [AmountCandidate]
    ) -> AmountCandidate? {
        candidates.max {
            if $0.score != $1.score { return $0.score < $1.score }
            // Ties are deterministic, but candidate evidence—not array order—does the ranking.
            return $0.lineIndex > $1.lineIndex
        }
    }

    private static func parsedMinorUnitsAllowingZero(_ value: String) -> Int64? {
        if let amount = try? LedgerAmount(input: value) { return amount.minorUnits }
        let digits = value.filter(\.isNumber)
        return !digits.isEmpty && digits.allSatisfy { $0 == "0" } ? 0 : nil
    }

    private static func containsInLineOrNearby(
        _ lines: [LedgerRecognizedTextLine],
        index: Int,
        keywords: [String]
    ) -> Bool {
        for candidateIndex in (index - 1)...(index + 1) where lines.indices.contains(candidateIndex) {
            if containsAny(lines[candidateIndex].text, keywords) { return true }
        }
        return false
    }

    private static func amountTokens(in text: String) -> [AmountToken] {
        let pattern = #"(?:[¥￥]\s*)?([0-9]{1,9}(?:[.,][0-9]{1,2})?)(?:\s*元)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: text),
                  let wholeRange = Range(match.range(at: 0), in: text)
            else { return nil }
            let whole = String(text[wholeRange])
            let value = String(text[valueRange]).replacingOccurrences(of: ",", with: ".")
            guard !looksLikeDateOrTime(value: value, whole: whole, matchRange: match.range(at: 0), in: text) else { return nil }
            let prefix = text[..<wholeRange.lowerBound].trimmingCharacters(in: .whitespaces)
            let hasExplicitSign = prefix.last == "-" || prefix.last == "+"
            let prefixLength = min(8, text.distance(from: text.startIndex, to: wholeRange.lowerBound))
            let contextStart = text.index(wholeRange.lowerBound, offsetBy: -prefixLength)
            let localContext = String(text[contextStart..<wholeRange.upperBound])
            return AmountToken(
                value: value,
                hasAmountMarker: whole.contains("¥") || whole.contains("￥") || whole.contains("元") || hasExplicitSign,
                localContext: localContext
            )
        }
    }

    private static func looksLikeDateOrTime(value: String, whole: String, matchRange: NSRange, in text: String) -> Bool {
        if value.count >= 7 && !value.contains(".") && !whole.contains("¥") && !whole.contains("￥") { return true }
        guard !whole.contains("¥"), !whole.contains("￥") else { return false }
        let utf16 = Array(text.utf16)
        let lower = matchRange.location
        let upper = matchRange.location + matchRange.length
        func isDigit(_ codeUnit: UInt16) -> Bool { (48...57).contains(codeUnit) }
        if lower >= 2, utf16[lower - 1] == 58, isDigit(utf16[lower - 2]) { return true }
        if upper + 1 < utf16.count, utf16[upper] == 58, isDigit(utf16[upper + 1]) { return true }
        let separators = CharacterSet(charactersIn: "-/.")
        if lower >= 2,
           let scalar = UnicodeScalar(utf16[lower - 1]),
           separators.contains(scalar),
           isDigit(utf16[lower - 2]) { return true }
        if upper + 1 < utf16.count,
           let scalar = UnicodeScalar(utf16[upper]),
           separators.contains(scalar),
           isDigit(utf16[upper + 1]) { return true }
        return false
    }

    private static func inferredKind(from text: String) -> LedgerEntryKind {
        // “极速退款”“退货包运费”等常出现在普通购物订单中，不能仅凭“退款”二字判为收入。
        let confirmedIncomeKeywords = [
            "退款成功", "退款金额", "退款到账", "已退款", "收款成功", "已收款", "到账金额", "工资到账", "奖金到账", "收入"
        ]
        return containsAny(text, confirmedIncomeKeywords) ? .income : .expense
    }

    private static func inferredMerchant(from lines: [LedgerRecognizedTextLine], amountLineIndex: Int?) -> String? {
        let joined = lines.map(\.text).joined(separator: "\n")
        if let labeled = labeledMerchant(in: lines) { return labeled }
        if let contextual = contextualMerchant(in: joined) { return contextual }
        return rankedMerchant(in: lines, amountLineIndex: amountLineIndex)
    }

    private static func labeledMerchant(in lines: [LedgerRecognizedTextLine]) -> String? {
        for (index, line) in lines.enumerated() {
            if containsAny(line.text, ["商户单号", "交易单号", "订单号"]) { continue }
            for label in merchantLabels where line.text.contains(label) {
                if label == "店铺",
                   line.text != label,
                   !line.text.hasPrefix("店铺:"),
                   !line.text.hasPrefix("店铺：") {
                    continue
                }
                let value = normalizedMerchantName(line.text
                    .replacingOccurrences(of: label, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "：: -")))
                if !emptyMerchantLabelValues.contains(value), isUsefulMerchant(value) { return value }
                if emptyMerchantLabelValues.contains(value), lines.indices.contains(index + 1) {
                    let nextValue = normalizedMerchantName(lines[index + 1].text)
                    if isUsefulMerchant(nextValue) { return nextValue }
                }
            }
        }
        return nil
    }

    private static func contextualMerchant(in text: String) -> String? {
        merchantContextRules.first { rule in
            rule.requiredKeywordGroups.allSatisfy { containsAny(text, $0) }
        }?.merchant
    }

    private static func rankedMerchant(
        in lines: [LedgerRecognizedTextLine],
        amountLineIndex: Int?
    ) -> String? {
        var candidates: [MerchantCandidate] = []
        for (index, line) in lines.enumerated() {
            let value = normalizedMerchantName(line.text)
            guard isUsefulMerchant(value) else { continue }
            candidates.append(MerchantCandidate(
                value: value,
                lineIndex: index,
                score: merchantScore(
                    value: value,
                    line: line,
                    at: index,
                    amountLineIndex: amountLineIndex
                )
            ))
        }
        return candidates.max {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.lineIndex > $1.lineIndex
        }?.value
    }

    private static func merchantScore(
        value: String,
        line: LedgerRecognizedTextLine,
        at index: Int,
        amountLineIndex: Int?
    ) -> Double {
        var score = Double(line.confidence) * 20 + min(line.height * 120, 24)
        if containsAny(value, merchantSignalKeywords) { score += 120 }
        if value.count <= 18 { score += 8 }
        if let amountLineIndex {
            let distance = abs(amountLineIndex - index)
            if distance <= 4 {
                score += Double(5 - distance) * 12
                // Payment result pages conventionally place the merchant above the total.
                if index < amountLineIndex { score += 8 }
            } else if index < amountLineIndex, distance <= 24 {
                score += Double(25 - distance) * 0.8
            }
        }
        return score
    }

    private static func isUsefulMerchant(_ value: String) -> Bool {
        guard value.count >= 2, value.count <= 40,
              !value.contains("*"),
              !value.contains("＊"),
              !containsAny(value, nonMerchantKeywords),
              !containsAny(value, promotionalMerchantKeywords),
              !merchantActionValues.contains(value),
              !containsAny(value, amountKeywords),
              amountTokens(in: value).isEmpty,
              value.rangeOfCharacter(from: .letters) != nil
        else { return false }
        return true
    }

    private static func normalizedMerchantName(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("回 ") { value.removeFirst(2) }
        if let range = value.range(of: "京东"), range.lowerBound != value.startIndex {
            value = String(value[..<range.lowerBound])
        }
        return value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: ".…＞>")
        ))
    }

    private static func inferredCategory(from text: String, merchant: String?, kind: LedgerEntryKind) -> String? {
        let value = text + "\n" + (merchant ?? "")
        if kind == .income {
            if containsAny(value, ["工资", "薪资", "薪酬"]) { return "工资" }
            if containsAny(value, ["奖金", "年终奖"]) { return "奖金" }
            return "其他收入"
        }
        // Confirmed mappings are deliberately narrow: generic words such as “农场” are not
        // sufficient evidence that an unrelated merchant belongs to food and dining.
        if let merchant,
           let rule = confirmedMerchantCategoryRules.first(where: {
               containsAny(merchant, $0.keywords)
           }) {
            return rule.category
        }
        return expenseCategoryRules.first {
            containsAny(value, $0.keywords)
        }?.category ?? "其它"
    }

    private static func inferredDate(from lines: [String], now: Date, calendar: Calendar) -> Date? {
        let todayPattern = #"今天\s*([0-9]{1,2}):([0-9]{2})"#
        if let expression = try? NSRegularExpression(pattern: todayPattern) {
            for line in lines {
                let range = NSRange(line.startIndex..., in: line)
                guard let match = expression.firstMatch(in: line, range: range),
                      let hourRange = Range(match.range(at: 1), in: line),
                      let minuteRange = Range(match.range(at: 2), in: line),
                      let hour = Int(line[hourRange]),
                      let minute = Int(line[minuteRange])
                else { continue }
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.hour = hour
                components.minute = minute
                components.second = 0
                if let date = calendar.date(from: components) { return date }
            }
        }

        let patterns = [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
            "yyyy.MM.dd HH:mm:ss", "yyyy.MM.dd HH:mm", "yyyy年M月d日 HH:mm:ss", "yyyy年M月d日 HH:mm",
            "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "yyyy年M月d日"
        ]
        for line in lines {
            for format in patterns {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = format
                formatter.isLenient = false
                if let match = firstDateSubstring(in: line, format: format), let date = formatter.date(from: match) {
                    return date
                }
            }
        }

        let monthDayPattern = #"([0-9]{1,2})月([0-9]{1,2})日(?:\s+([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?)?"#
        guard let expression = try? NSRegularExpression(pattern: monthDayPattern) else { return nil }
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = expression.firstMatch(in: line, range: range) else { continue }
            func integer(_ index: Int) -> Int? {
                guard match.range(at: index).location != NSNotFound,
                      let range = Range(match.range(at: index), in: line)
                else { return nil }
                return Int(line[range])
            }
            var components = calendar.dateComponents([.year], from: now)
            components.month = integer(1)
            components.day = integer(2)
            components.hour = integer(3) ?? 12
            components.minute = integer(4) ?? 0
            components.second = integer(5) ?? 0
            if let date = calendar.date(from: components) { return date }
        }
        return nil
    }

    private static func firstDateSubstring(in text: String, format: String) -> String? {
        let pattern: String
        if format.contains("年") {
            pattern = format.contains("HH")
                ? #"[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日\s+[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?"#
                : #"[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日"#
        } else {
            let escapedSeparator = format.contains("/") ? "/" : format.contains(".") ? #"\."# : "-"
            pattern = format.contains("HH")
                ? "[0-9]{4}\(escapedSeparator)[0-9]{1,2}\(escapedSeparator)[0-9]{1,2}\\s+[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?"
                : "[0-9]{4}\(escapedSeparator)[0-9]{1,2}\(escapedSeparator)[0-9]{1,2}"
        }
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        let value = String(text[range])
        if format.hasSuffix(":ss"), value.split(separator: ":").count < 3 { return nil }
        return value
    }

    private static func containsAny(_ text: String, _ values: [String]) -> Bool {
        values.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func normalize(_ text: String) -> String {
        var result = text.precomposedStringWithCompatibilityMapping
        let replacements = ["，": ",", "。": ".", "：": ":", "﹣": "-", "−": "-"]
        for (source, target) in replacements { result = result.replacingOccurrences(of: source, with: target) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
