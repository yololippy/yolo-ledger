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
        .accessibilityIdentifier("month.title")
        .accessibilityLabel("选择月份")
        .accessibilityValue(displayedMonth.formatted(.dateTime.year().month()))
        #if os(iOS)
        .sheet(isPresented: $isPresented) {
            MonthPickerView(displayedMonth: displayedMonth, selectMonth: selectMonth)
                .presentationDetents([.height(392)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(theme.primarySoft.opacity(0.55))
                .interactiveDismissDisabled()
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

            navigationHeader

            Group {
                if mode == .month {
                    monthGrid
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    yearGrid
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.snappy(duration: 0.22), value: mode)
            .contentShape(Rectangle())
            .simultaneousGesture(horizontalPagingGesture)

            footer
        }
        .padding(.horizontal, 18)
        .padding(.bottom, bottomPadding)
        .foregroundStyle(theme.ink)
        .background(theme.primarySoft.opacity(0.55).ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(theme.surface.opacity(0.78), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭月份选择")
            .accessibilityIdentifier("month-picker.close")
            .padding(.top, 2)
            .padding(.trailing, 12)
        }
    }

    private var navigationHeader: some View {
        HStack(spacing: 18) {
            navigationButton(systemName: "chevron.left") {
                if mode == .month {
                    selectedYear -= 1
                } else {
                    yearPageStart -= 12
                }
            }
            .accessibilityIdentifier(mode == .month ? "month-picker.year.previous" : "month-picker.range.previous")

            Spacer(minLength: 0)

            if mode == .month {
                Button {
                    yearPageStart = Self.initialYearPage(containing: selectedYear)
                    withAnimation { mode = .year }
                } label: {
                    HStack(spacing: 5) {
                        Text(verbatim: "\(selectedYear) 年")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("month-picker.year-toggle")
            } else {
                Text(verbatim: "\(yearPageStart)–\(yearPageStart + 11)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.primary)
                    .accessibilityIdentifier("month-picker.year-range")
            }

            Spacer(minLength: 0)

            navigationButton(systemName: "chevron.right") {
                if mode == .month {
                    selectedYear += 1
                } else {
                    yearPageStart += 12
                }
            }
            .accessibilityIdentifier(mode == .month ? "month-picker.year.next" : "month-picker.range.next")
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(1...12, id: \.self) { month in
                selectionButton(
                    title: "\(month)月",
                    isSelected: selectedYear == highlightedYear && month == selectedMonth,
                    identifier: "month-picker.month.\(month)"
                ) {
                    selectedMonth = month
                    commit(year: selectedYear, month: month)
                }
            }
        }
        .accessibilityIdentifier("month-picker.month-grid")
    }

    private var yearGrid: some View {
        LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(yearPageStart..<(yearPageStart + 12), id: \.self) { year in
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
        .accessibilityIdentifier("month-picker.year-grid")
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

    private var horizontalPagingGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                guard abs(horizontalDistance) > abs(value.translation.height),
                      abs(horizontalDistance) >= 40 else { return }
                withAnimation(.snappy(duration: 0.22)) {
                    if mode == .month {
                        selectedYear += horizontalDistance < 0 ? 1 : -1
                    } else {
                        yearPageStart += horizontalDistance < 0 ? 12 : -12
                    }
                }
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
        .accessibilityIdentifier(identifier)
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
