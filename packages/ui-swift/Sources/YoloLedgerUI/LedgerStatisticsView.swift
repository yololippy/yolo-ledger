#if os(iOS)
import Foundation
import SwiftUI
import YoloLedgerCore

private struct LedgerStatisticsLoadKey: Hashable {
    let bookID: UUID?
    let month: Date
    let kind: String
    let revision: Int
}

private struct LedgerStatisticsDrilldown: Identifiable {
    let id: String
    let title: String
    let entryIDs: [UUID]
}

@MainActor
struct LedgerStatisticsView: View {
    @Environment(\.ledgerTheme) private var theme
    let model: LedgerAppModel
    let controller: LedgerStatisticsController
    @State private var showsAllCategories = false
    @State private var showsAllEntries = false
    @State private var drilldown: LedgerStatisticsDrilldown?
    @State private var selectedEntry: LedgerEntry?

    private var loadKey: LedgerStatisticsLoadKey {
        LedgerStatisticsLoadKey(
            bookID: model.selectedBookID,
            month: model.displayedMonth,
            kind: controller.kind.rawValue,
            revision: model.statisticsRevision
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    monthHeading
                    summaryCard
                    kindPicker
                    statisticsContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await loadStatistics() }
        }
        .task(id: loadKey) { await loadStatistics() }
        .onChange(of: controller.context) { _, _ in
            showsAllCategories = false
            showsAllEntries = false
        }
        .sheet(item: $drilldown) { context in
            LedgerStatisticsDrilldownView(
                model: model,
                controller: controller,
                context: context
            )
        }
        .fullScreenCover(item: $selectedEntry) { entry in
            EntryDetailView(model: model, entryID: entry.id, fallbackEntry: entry)
        }
    }

    private var pageHeader: some View {
        HStack {
            Menu {
                ForEach(model.books) { book in
                    Button(book.name) { Task { await model.selectBook(book.id) } }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(model.selectedBook?.name ?? "选择账本")
                        .font(.system(size: 20, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .accessibilityIdentifier("ledger.book-picker")
            .disabled(model.isSaving)
            Spacer()
            Text("账单")
                .font(.system(size: 13))
                .foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 21)
        .padding(.vertical, 17)
    }

    private var monthHeading: some View {
        HStack {
            Button { Task { await model.moveMonth(by: -1) } } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: 32)
            }
            .accessibilityIdentifier("month.previous")
            Spacer()
            MonthPickerButton(displayedMonth: model.displayedMonth) { month in
                Task { await model.selectMonth(month) }
            }
            Spacer()
            Button { Task { await model.moveMonth(by: 1) } } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: 32)
            }
            .accessibilityIdentifier("month.next")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var summaryCard: some View {
        if let summary = try? model.monthSummary() {
            VStack(alignment: .leading, spacing: 20) {
                Text("本月结余").font(.system(size: 17, weight: .bold))
                Text("¥ \(LedgerAmount.format(minorUnits: summary.balanceMinorUnits))")
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityIdentifier("summary.balance")
                summaryBar(
                    "本月支出",
                    amount: summary.expenseMinorUnits,
                    other: summary.incomeMinorUnits,
                    color: theme.expense,
                    identifier: "summary.expense"
                )
                summaryBar(
                    "本月收入",
                    amount: summary.incomeMinorUnits,
                    other: summary.expenseMinorUnits,
                    color: theme.income,
                    identifier: "summary.income"
                )
            }
            .padding(22)
            .paperCard()
        } else {
            Text("本月汇总暂时无法计算，请检查账目金额。")
                .foregroundStyle(theme.error)
        }
    }

    private func summaryBar(
        _ title: String,
        amount: Int64,
        other: Int64,
        color: Color,
        identifier: String
    ) -> some View {
        HStack(spacing: 9) {
            Text(title).font(.system(size: 13)).foregroundStyle(theme.muted)
            GeometryReader { proxy in
                Capsule().fill(color.opacity(0.13))
                Capsule().fill(color).frame(
                    width: proxy.size.width * (amount == 0 ? 0 : max(
                        0.06,
                        Double(amount) / max(Double(amount), Double(other), 1)
                    ))
                )
            }
            .frame(height: 11)
            Text("¥\(LedgerAmount.format(minorUnits: amount))")
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier(identifier)
        }
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            kindButton(.expense)
            kindButton(.income)
        }
        .padding(5)
        .background(theme.primarySoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statistics.kind-picker")
    }

    private func kindButton(_ kind: LedgerEntryKind) -> some View {
        Button {
            controller.selectKind(kind)
        } label: {
            Text(kind.title)
                .font(.system(size: 15, weight: controller.kind == kind ? .bold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    controller.kind == kind ? theme.surface : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("statistics.kind.\(kind.rawValue)")
        .accessibilityAddTraits(controller.kind == kind ? .isSelected : [])
    }

    @ViewBuilder
    private var statisticsContent: some View {
        if let error = controller.loadError {
            VStack(alignment: .leading, spacing: 12) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.error)
                Button("重试统计") { Task { await loadStatistics() } }
                    .buttonStyle(PaperButtonStyle(fill: theme.primarySoft))
                    .accessibilityIdentifier("statistics.retry")
            }
            .padding(18)
            .paperCard()
            .accessibilityIdentifier("statistics.error")
        }

        if let statistics = controller.statistics {
            trendCard(statistics.trend)
            categoryShareCard(statistics.snapshot)
            categoryRankingCard(statistics.snapshot)
            entryRankingCard(statistics.snapshot)
        } else if controller.isLoading {
            ProgressView("正在计算统计")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 46)
                .accessibilityIdentifier("statistics.loading")
        } else if controller.loadError == nil {
            emptyStatisticsCard
        }
    }

    private func trendCard(_ points: [LedgerMonthlyTrendPoint]) -> some View {
        let maximum = max(points.map(\.amountMinorUnits).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近 6 个月").font(.system(size: 17, weight: .bold))
                Spacer()
                Text(controller.kind.title + "趋势")
                    .font(.caption)
                    .foregroundStyle(theme.muted)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(points) { point in
                    Button {
                        guard point.entryCount > 0 else { return }
                        drilldown = LedgerStatisticsDrilldown(
                            id: "month-\(point.dateRange.start.timeIntervalSinceReferenceDate)-\(controller.kind.rawValue)",
                            title: point.dateRange.start.formatted(.dateTime.year().month(.wide)),
                            entryIDs: point.entryIDs
                        )
                    } label: {
                        VStack(spacing: 4) {
                            Text(shortAmount(point.amountMinorUnits))
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(theme.primarySoft.opacity(0.5))
                                if point.amountMinorUnits > 0 {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(controller.kind == .expense ? theme.expense : theme.income)
                                        .frame(height: max(
                                            4,
                                            58 * CGFloat(Double(point.amountMinorUnits) / Double(maximum))
                                        ))
                                }
                            }
                            .frame(width: 14, height: 58)
                            Text(point.dateRange.start, format: .dateTime.month(.twoDigits))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(point.entryCount == 0)
                    .opacity(point.entryCount == 0 ? 0.55 : 1)
                    .accessibilityIdentifier("statistics.trend.month.\(monthIdentifier(point.dateRange.start))")
                    .accessibilityLabel(
                        "\(point.dateRange.start.formatted(.dateTime.year().month(.wide)))，\(controller.kind.title) \(currency(point.amountMinorUnits))，\(point.entryCount) 笔"
                    )
                }
            }
        }
        .padding(16)
        .paperCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statistics.trend")
    }

    private func categoryShareCard(_ snapshot: LedgerStatisticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("分类占比").font(.system(size: 17, weight: .bold))
            if snapshot.totalMinorUnits == 0 {
                ZStack {
                    Circle().stroke(theme.primarySoft, lineWidth: 18)
                    VStack(spacing: 3) {
                        Text(controller.kind.title + "总额").font(.caption).foregroundStyle(theme.muted)
                        Text("¥0.00").font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                }
                .frame(width: 170, height: 170)
                .frame(maxWidth: .infinity)
                Text("本月暂无\(controller.kind.title)账目")
                    .font(.caption)
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    ForEach(donutSegments(snapshot)) { segment in
                        Circle()
                            .trim(from: segment.start, to: segment.end)
                            .stroke(
                                categoryColor(segment.category.categoryID),
                                style: StrokeStyle(lineWidth: 19, lineCap: .butt)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 3) {
                        Text(controller.kind.title + "总额")
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                        Text(currency(snapshot.totalMinorUnits))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .padding(24)
                }
                .frame(width: 180, height: 180)
                .frame(maxWidth: .infinity)
                ForEach(snapshot.categories.prefix(4)) { category in
                    HStack(spacing: 8) {
                        Circle().fill(categoryColor(category.categoryID)).frame(width: 9, height: 9)
                        Text(category.categoryName).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(percentageText(category.share)) · \(category.entryCount) 笔")
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                    }
                }
                if snapshot.categories.count > 4 {
                    Text("其余 \(snapshot.categories.count - 4) 个分类请在下方排行查看")
                        .font(.caption2)
                        .foregroundStyle(theme.muted)
                }
            }
        }
        .padding(18)
        .paperCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statistics.donut")
        .accessibilityLabel(
            "分类占比，\(controller.kind.title)总额 \(currency(snapshot.totalMinorUnits))，\(snapshot.categories.count) 个分类"
        )
    }

    private func categoryRankingCard(_ snapshot: LedgerStatisticsSnapshot) -> some View {
        let categories = showsAllCategories ? snapshot.categories : Array(snapshot.categories.prefix(3))
        let maximum = max(snapshot.categories.first?.amountMinorUnits ?? 0, 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text("类目排行").font(.system(size: 17, weight: .bold))
            if categories.isEmpty {
                Text("本月暂无可排行的分类")
                    .font(.caption)
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    Button {
                        drilldown = LedgerStatisticsDrilldown(
                            id: "category-\(category.categoryID.uuidString)-\(controller.kind.rawValue)",
                            title: category.categoryName,
                            entryIDs: category.entryIDs
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(theme.primary)
                                    .frame(width: 20)
                                CategoryBadge(name: category.categoryName, size: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(category.categoryName).font(.system(size: 14, weight: .semibold))
                                    Text("\(percentageText(category.share)) · \(category.entryCount) 笔")
                                        .font(.caption2)
                                        .foregroundStyle(theme.muted)
                                }
                                Spacer()
                                Text(currency(category.amountMinorUnits))
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                            GeometryReader { proxy in
                                Capsule().fill(theme.primarySoft.opacity(0.5))
                                Capsule()
                                    .fill(categoryColor(category.categoryID))
                                    .frame(width: proxy.size.width * CGFloat(
                                        Double(category.amountMinorUnits) / Double(maximum)
                                    ))
                            }
                            .frame(height: 7)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("statistics.category.\(category.categoryID.uuidString)")
                    .accessibilityLabel(
                        "第 \(index + 1) 名，\(category.categoryName)，\(currency(category.amountMinorUnits))，\(percentageText(category.share))，\(category.entryCount) 笔"
                    )
                }
                if snapshot.categories.count > 3 {
                    Button(showsAllCategories ? "收起" : "查看全部 \(snapshot.categories.count) 个分类") {
                        withAnimation(.easeInOut(duration: 0.2)) { showsAllCategories.toggle() }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .accessibilityIdentifier("statistics.categories.expand")
                    .accessibilityValue(showsAllCategories ? "已展开" : "已收起")
                }
            }
        }
        .padding(18)
        .paperCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statistics.categories")
    }

    private func entryRankingCard(_ snapshot: LedgerStatisticsSnapshot) -> some View {
        let entries = showsAllEntries ? snapshot.rankedEntries : Array(snapshot.rankedEntries.prefix(3))
        return VStack(alignment: .leading, spacing: 14) {
            Text("明细排行").font(.system(size: 17, weight: .bold))
            if entries.isEmpty {
                Text("本月暂无可排行的账目")
                    .font(.caption)
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button { selectedEntry = entry } label: {
                        HStack(spacing: 11) {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.primary)
                                .frame(width: 20)
                            CategoryBadge(name: model.categoryName(entry.categoryID), size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.categoryName(entry.categoryID))
                                    .font(.system(size: 14, weight: .semibold))
                                Text(entry.note.isEmpty ? "无备注" : entry.note)
                                    .font(.caption)
                                    .foregroundStyle(theme.muted)
                                    .lineLimit(1)
                                Text(entry.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                                    .font(.caption2)
                                    .foregroundStyle(theme.muted)
                            }
                            Spacer(minLength: 8)
                            Text(currency(entry.amount.minorUnits))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("statistics.entry.\(entry.id.uuidString)")
                    .accessibilityLabel(
                        "第 \(index + 1) 名，\(model.categoryName(entry.categoryID))，\(currency(entry.amount.minorUnits))，\(entry.note)，\(entry.date.formatted(.dateTime.year().month().day()))"
                    )
                }
                if snapshot.rankedEntries.count > 3 {
                    Button(showsAllEntries ? "收起" : "查看全部 \(snapshot.rankedEntries.count) 笔") {
                        withAnimation(.easeInOut(duration: 0.2)) { showsAllEntries.toggle() }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .accessibilityIdentifier("statistics.entries.expand")
                    .accessibilityValue(showsAllEntries ? "已展开" : "已收起")
                }
            }
        }
        .padding(18)
        .paperCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statistics.entries")
    }

    private var emptyStatisticsCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.pie")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(theme.primary)
            Text("暂无统计数据").font(.headline)
            Text("本月记一笔后，这里会显示趋势和排行。")
                .font(.caption)
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .paperCard()
        .accessibilityIdentifier("statistics.empty")
    }

    private func loadStatistics() async {
        guard let bookID = model.selectedBookID else { return }
        await controller.load(
            bookID: bookID,
            monthContaining: model.displayedMonth,
            categories: model.categories
        )
    }

    private func currency(_ minorUnits: Int64) -> String {
        "¥" + LedgerAmount.format(minorUnits: minorUnits)
    }

    private func shortAmount(_ minorUnits: Int64) -> String {
        let major = Double(minorUnits) / 100
        if major >= 10_000 { return String(format: "%.1f万", major / 10_000) }
        if major >= 1_000 { return String(format: "%.1fk", major / 1_000) }
        return LedgerAmount.format(minorUnits: minorUnits)
    }

    private func percentageText(_ ratio: LedgerStatisticsRatio) -> String {
        guard ratio.denominatorMinorUnits > 0 else { return "0%" }
        var numerator = Decimal(ratio.numeratorMinorUnits)
        numerator *= 100
        let value = numerator / Decimal(ratio.denominatorMinorUnits)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return (formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0") + "%"
    }

    private func monthIdentifier(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private func categoryColor(_ id: UUID) -> Color {
        let palette = [
            theme.primary,
            theme.expense,
            theme.income,
            theme.accent,
            theme.artwork.travel,
            theme.artwork.shopping,
            theme.artwork.other,
            theme.artwork.yellow,
        ]
        let index = id.uuidString.utf8.reduce(0) { (partial, byte) in
            (partial &* 31 &+ Int(byte)) % palette.count
        }
        return palette[index]
    }

    private func donutSegments(_ snapshot: LedgerStatisticsSnapshot) -> [DonutSegment] {
        guard snapshot.totalMinorUnits > 0 else { return [] }
        var cursor: CGFloat = 0
        return snapshot.categories.enumerated().map { index, category in
            let start = cursor
            let fraction = CGFloat(Double(category.amountMinorUnits) / Double(snapshot.totalMinorUnits))
            cursor = index == snapshot.categories.count - 1 ? 1 : min(1, cursor + fraction)
            return DonutSegment(category: category, start: start, end: cursor)
        }
    }
}

private struct DonutSegment: Identifiable {
    let category: LedgerCategoryStatistics
    let start: CGFloat
    let end: CGFloat
    var id: UUID { category.categoryID }
}

@MainActor
private struct LedgerStatisticsDrilldownView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ledgerTheme) private var theme
    let model: LedgerAppModel
    let controller: LedgerStatisticsController
    let context: LedgerStatisticsDrilldown
    @State private var selectedEntry: LedgerEntry?

    private var entries: [LedgerEntry] { controller.entries(for: context.entryIDs) }

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button { selectedEntry = entry } label: {
                    HStack(spacing: 12) {
                        CategoryBadge(name: model.categoryName(entry.categoryID), size: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.categoryName(entry.categoryID)).font(.headline)
                            Text(entry.note.isEmpty ? "无备注" : entry.note)
                                .font(.caption)
                                .foregroundStyle(theme.muted)
                                .lineLimit(1)
                            Text(entry.date, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                                .font(.caption2)
                                .foregroundStyle(theme.muted)
                        }
                        Spacer()
                        Text("¥" + entry.amount.decimalString)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("statistics.drilldown.entry.\(entry.id.uuidString)")
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle(context.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("statistics.drilldown.close")
                }
            }
        }
        .accessibilityIdentifier("statistics.drilldown")
        .fullScreenCover(item: $selectedEntry) { entry in
            EntryDetailView(model: model, entryID: entry.id, fallbackEntry: entry)
        }
    }
}
#endif
