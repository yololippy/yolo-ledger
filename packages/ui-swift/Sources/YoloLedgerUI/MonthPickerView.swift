import SwiftUI

struct MonthPickerButton: View {
    @Environment(\.ledgerTheme) private var theme
    @State private var isPresented = false

    let displayedMonth: Date
    let selectMonth: (Date) -> Void

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 5) {
                Text(displayedMonth, format: .dateTime.year().month())
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(theme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(theme.primarySoft.opacity(0.72), in: Capsule())
        }
        .buttonStyle(.plain)
        .pagingAccessibilityIdentifier("month.title")
        .accessibilityLabel("选择月份")
        .accessibilityValue(displayedMonth.formatted(.dateTime.year().month()))
        #if os(iOS)
        .sheet(isPresented: $isPresented) {
            MonthPickerView(displayedMonth: displayedMonth, selectMonth: selectMonth)
                .presentationDetents([.height(392)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(theme.primarySoft.opacity(0.55))
        }
        #else
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            MonthPickerView(displayedMonth: displayedMonth, selectMonth: selectMonth)
                .frame(width: 370, height: 430)
        }
        #endif
    }
}

private struct MonthPickerView: View {
    private enum Mode {
        case month
        case year
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.ledgerTheme) private var theme
    @State private var mode: Mode = .month
    @State private var selectedYear: Int
    @State private var highlightedYear: Int
    @State private var selectedMonth: Int
    @State private var yearPageStart: Int

    private let calendar: Calendar
    private let selectMonth: (Date) -> Void

    init(displayedMonth: Date, selectMonth: @escaping (Date) -> Void) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        let year = components.year ?? calendar.component(.year, from: Date())
        let month = components.month ?? calendar.component(.month, from: Date())
        self.calendar = calendar
        self.selectMonth = selectMonth
        _selectedYear = State(initialValue: year)
        _highlightedYear = State(initialValue: year)
        _selectedMonth = State(initialValue: month)
        _yearPageStart = State(initialValue: Self.initialYearPage(containing: year))
    }

    var body: some View {
        VStack(spacing: sectionSpacing) {
            Text(mode == .month ? "选择月份" : "选择年份")
                .font(.system(size: 17, weight: .bold))
                .padding(.top, topPadding)

            Group {
                if mode == .month {
                    monthPager
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    yearPager
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.snappy(duration: 0.22), value: mode)

            footer
        }
        .padding(.horizontal, 18)
        .padding(.bottom, bottomPadding)
        .foregroundStyle(theme.ink)
        .background(theme.primarySoft.opacity(0.55).ignoresSafeArea())
    }

    private var monthPager: some View {
        HorizontalPagingView(
            page: selectedYear,
            previousPage: { $0 - 1 },
            nextPage: { $0 + 1 },
            selectPage: { selectedYear = $0 },
            gesturePriority: .high,
            debugIdentifier: "month-picker.year-pager"
        ) { year, paging in
            VStack(spacing: sectionSpacing) {
                HStack(spacing: 18) {
                    navigationButton(systemName: "chevron.left", action: paging.moveToPrevious)
                        .pagingAccessibilityIdentifier("month-picker.year.previous")

                    Spacer(minLength: 0)

                    yearToggle(year: year)

                    Spacer(minLength: 0)

                    navigationButton(systemName: "chevron.right", action: paging.moveToNext)
                        .pagingAccessibilityIdentifier("month-picker.year.next")
                }

                monthGrid(for: year)
            }
        }
    }

    private var yearPager: some View {
        HorizontalPagingView(
            page: yearPageStart,
            previousPage: { $0 - 12 },
            nextPage: { $0 + 12 },
            selectPage: { yearPageStart = $0 },
            gesturePriority: .high,
            debugIdentifier: "month-picker.range-pager"
        ) { pageStart, paging in
            VStack(spacing: sectionSpacing) {
                HStack(spacing: 18) {
                    navigationButton(systemName: "chevron.left", action: paging.moveToPrevious)
                        .pagingAccessibilityIdentifier("month-picker.range.previous")

                    Spacer(minLength: 0)

                    Text(verbatim: "\(pageStart)–\(pageStart + 11)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(theme.primary)
                        .pagingAccessibilityIdentifier("month-picker.year-range")

                    Spacer(minLength: 0)

                    navigationButton(systemName: "chevron.right", action: paging.moveToNext)
                        .pagingAccessibilityIdentifier("month-picker.range.next")
                }

                yearGrid(pageStart: pageStart)
            }
        }
    }

    private func yearToggle(year: Int) -> some View {
        Button {
            yearPageStart = Self.initialYearPage(containing: year)
            withAnimation { mode = .year }
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: "\(year) 年")
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(theme.primary)
        }
        .buttonStyle(.plain)
        .pagingAccessibilityIdentifier("month-picker.year-toggle")
    }

    private func monthGrid(for year: Int) -> some View {
        LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(1...12, id: \.self) { month in
                selectionButton(
                    title: "\(month)月",
                    isSelected: year == highlightedYear && month == selectedMonth,
                    identifier: "month-picker.month.\(month)"
                ) {
                    selectedYear = year
                    selectedMonth = month
                    commit(year: year, month: month)
                }
            }
        }
        .pagingAccessibilityIdentifier("month-picker.month-grid")
    }

    private func yearGrid(pageStart: Int) -> some View {
        LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(pageStart..<(pageStart + 12), id: \.self) { year in
                selectionButton(
                    title: String(year),
                    isSelected: year == selectedYear,
                    identifier: "month-picker.year.\(year)"
                ) {
                    selectedYear = year
                    withAnimation { mode = .month }
                }
            }
        }
        .pagingAccessibilityIdentifier("month-picker.year-grid")
    }

    @ViewBuilder
    private var footer: some View {
        if mode == .month {
            Button {
                let now = Date()
                withAnimation {
                    selectedYear = calendar.component(.year, from: now)
                    highlightedYear = selectedYear
                    selectedMonth = calendar.component(.month, from: now)
                }
            } label: {
                Text("回到本月")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(theme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("month-picker.current")
        } else {
            Button {
                withAnimation { mode = .month }
            } label: {
                Text("返回月份")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(theme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("month-picker.back-to-months")
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3)
    }

    private var sectionSpacing: CGFloat {
        #if os(iOS)
        10
        #else
        14
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(iOS)
        8
        #else
        10
        #endif
    }

    private var selectionHeight: CGFloat {
        #if os(iOS)
        46
        #else
        48
        #endif
    }

    private var topPadding: CGFloat {
        #if os(iOS)
        6
        #else
        9
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(iOS)
        0
        #else
        18
        #endif
    }

    private func navigationButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(theme.surface.opacity(0.78), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func selectionButton(
        title: String,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? theme.onPrimary : theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: selectionHeight)
                .background(
                    isSelected ? theme.primary : theme.surface.opacity(0.76),
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
        .buttonStyle(.plain)
        .pagingAccessibilityIdentifier(identifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func commit(year: Int, month: Int) {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return }
        selectMonth(date)
        dismiss()
    }

    private static func initialYearPage(containing year: Int) -> Int {
        year - year % 10
    }
}
