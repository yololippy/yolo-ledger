import SwiftUI
import YoloLedgerCore

private enum LedgerDestination: String, CaseIterable, Identifiable {
    case details, bills, books, settings
    var id: Self { self }
    var title: String {
        switch self { case .bills: "账单"; case .details: "明细"; case .books: "账本"; case .settings: "我的" }
    }
    var symbol: String {
        switch self { case .bills: "calendar"; case .details: "receipt"; case .books: "book.closed"; case .settings: "person.crop.circle" }
    }
}

@MainActor
public struct YoloLedgerRootView: View {
    @State private var model: LedgerAppModel
    @State private var selection: LedgerDestination = .bills
    @State private var showsNewEntry = false
    @State private var selectedEntry: LedgerEntry?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ledgerTheme) private var theme

    public init(repository: any LedgerRepository) {
        _model = State(initialValue: LedgerAppModel(repository: repository))
    }

    public var body: some View {
        ZStack {
            PaperBackground()
            if model.hasLoaded { navigation }
            else if let message = model.loadError {
                VStack(spacing: 20) {
                    Text("账目读取失败").font(.title3.bold())
                    Text(message)
                    Button("重试") { Task { await model.refresh() } }.buttonStyle(PaperButtonStyle(fill: theme.primarySoft))
                        .accessibilityIdentifier("ledger.reload")
                }.padding(30).frame(maxWidth: 460)
            } else { ProgressView("正在读取本地账目") }
        }
        .foregroundStyle(theme.ink)
        .font(.system(.body, design: .rounded))
        .tint(theme.primary)
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, value in
            if value == .active { Task { await model.refresh() } }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showsNewEntry) { EntryEditorView(model: model) }
        #else
        .sheet(isPresented: $showsNewEntry) { EntryEditorView(model: model) }
        #endif
        .sheet(item: $selectedEntry) { EntryDetailView(model: model, entryID: $0.id) }
    }

    private var navigation: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("有落").font(.system(size: 30, weight: .heavy, design: .rounded)).padding(.bottom, 2)
                Text("把生活，一笔笔留下").font(.caption).foregroundStyle(theme.muted).padding(.bottom, 20)
                ForEach(LedgerDestination.allCases) { destination in
                    Button { selection = destination } label: {
                        Label(destination.title, systemImage: destination.symbol).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13).background(selection == destination ? theme.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .overlay { if selection == destination { RoundedRectangle(cornerRadius: 10).stroke(theme.ink, lineWidth: 1.5) } }
                    }.buttonStyle(.plain).accessibilityIdentifier("navigation.\(destination.rawValue)")
                }
                Spacer()
                addButton
                Text("YoloLedger · 本地账本").font(.caption2).foregroundStyle(theme.muted)
            }.padding(22).frame(width: 195).background(theme.primarySoft)
            Rectangle().fill(theme.ink).frame(width: 1)
            destinationView.frame(maxWidth: .infinity)
        }
        #else
        destinationView.safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        #endif
    }

    private var addButton: some View {
        Button { showsNewEntry = true } label: {
            #if os(macOS)
            Label("记一笔", systemImage: "plus").fontWeight(.semibold).padding(14).frame(maxWidth: .infinity).paperCard()
            #else
            Image(systemName: "plus").font(.system(size: 31, weight: .medium))
                .frame(width: 62, height: 62).background(theme.surface, in: Circle())
                .overlay { Circle().stroke(theme.ink, lineWidth: 2) }
                .background(Circle().fill(theme.shadow).offset(y: 4))
            #endif
        }.buttonStyle(.plain)
            .disabled(model.books.isEmpty || model.isSaving || showsNewEntry || selectedEntry != nil)
            .accessibilityLabel("记一笔").accessibilityIdentifier("entry.add")
            .keyboardShortcut("n", modifiers: .command)
    }

    #if os(iOS)
    private var bottomBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            navButton(.details); navButton(.bills)
            addButton.frame(maxWidth: .infinity).offset(y: -13)
            navButton(.books); navButton(.settings)
        }.padding(.top, 9).padding(.bottom, 4)
            .background {
                theme.navigationBackground.ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .top) { Rectangle().fill(theme.ink).frame(height: 1) }
            }
    }

    private func navButton(_ destination: LedgerDestination) -> some View {
        Button { selection = destination } label: {
            VStack(spacing: 4) {
                Image(systemName: destination.symbol).font(.system(size: 24, weight: .regular))
                    .frame(width: 39,height: 30)
                    .background(selection == destination ? theme.surface.opacity(0.9) : .clear, in: RoundedRectangle(cornerRadius: 6))
                Text(destination.title).font(.system(size: 12, weight: selection == destination ? .bold : .regular))
            }.frame(maxWidth: .infinity).padding(.bottom, 3)
        }.buttonStyle(.plain).accessibilityIdentifier("navigation.\(destination.rawValue)")
            .accessibilityAddTraits(selection == destination ? .isSelected : [])
    }
    #endif

    private var destinationView: some View {
        VStack(spacing: 0) {
            if let message = model.loadError {
                HStack {
                    Text(message).font(.caption).foregroundStyle(theme.error).accessibilityIdentifier("ledger.refresh-error")
                    Spacer()
                    Button("重试") { Task { await model.refresh() } }.accessibilityIdentifier("ledger.reload")
                }.padding(14).background(theme.primarySoft)
            }
            switch selection {
            case .bills, .details:
                LedgerEntriesView(model: model, isMonthly: selection == .bills) { selectedEntry = $0 }
            case .books: LedgerBooksView(model: model)
            case .settings: LedgerProfileView()
            }
        }
    }
}

@MainActor
private struct LedgerEntriesView: View {
    @Environment(\.ledgerTheme) private var theme
    let model: LedgerAppModel
    let isMonthly: Bool
    let onSelect: (LedgerEntry) -> Void
    private var entries: [LedgerEntry] { isMonthly ? model.monthEntries : model.calendarEntries }
    private var days: [Date] { Array(Set(entries.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    ForEach(model.books) { book in Button(book.name) { model.selectBook(book.id) } }
                } label: {
                    HStack(spacing: 7) {
                        Text(model.selectedBook?.name ?? "选择账本").font(.system(size: 20, weight: .bold))
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                }.accessibilityIdentifier("ledger.book-picker").disabled(model.isSaving)
                Spacer()
                Text(isMonthly ? "账单" : "明细 / 日历").font(.system(size: 13)).foregroundStyle(theme.muted)
            }.padding(.horizontal, 21).padding(.vertical, 17)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if isMonthly { monthHeading; summaryCard }
                    else { LedgerCalendarView(model: model) }
                    HStack {
                        Text(isMonthly ? "收支记录" : model.selectedDay == nil ? "本月记录" : "当日记录").font(.system(size: 19, weight: .bold))
                        Spacer()
                        Text("\(entries.count) 笔").font(.caption).foregroundStyle(theme.muted)
                    }
                    if entries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "receipt").font(.system(size: 32,weight: .ultraLight))
                                .padding(18).background(theme.primarySoft, in: Circle())
                            Text(isMonthly ? "暂无账单" : "暂无明细").font(.headline)
                            #if os(macOS)
                            Text("点左侧“记一笔”，记下生活的第一笔").font(.caption).foregroundStyle(theme.muted)
                            #else
                            Text("点下方 ＋，记下生活的第一笔").font(.caption).foregroundStyle(theme.muted)
                            #endif
                        }.frame(maxWidth: .infinity).padding(.vertical, 28)
                    } else {
                        ForEach(days, id: \.self) { day in
                            VStack(spacing: 4) {
                                dayHeading(day)
                                ForEach(entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { entry in
                                    entryRow(entry)
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 24)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.refreshable { await model.refresh() }
        }
    }

    private var monthHeading: some View {
        HStack {
            Button { model.moveMonth(by: -1) } label: { Image(systemName: "chevron.left").frame(width: 32,height: 32) }.accessibilityIdentifier("month.previous")
            Spacer()
            MonthPickerButton(displayedMonth: model.displayedMonth) { model.selectMonth($0) }
            Spacer()
            Button { model.moveMonth(by: 1) } label: { Image(systemName: "chevron.right").frame(width: 32,height: 32) }.accessibilityIdentifier("month.next")
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var summaryCard: some View {
        if let summary = try? model.monthSummary() {
            VStack(alignment: .leading, spacing: 20) {
                Text("本月结余").font(.system(size: 17, weight: .bold))
                Text("¥ \(LedgerAmount.format(minorUnits: summary.balanceMinorUnits))")
                    .font(.system(size: 34,weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(theme.accent)
                    .minimumScaleFactor(0.5).lineLimit(1).accessibilityIdentifier("summary.balance")
                summaryBar("本月支出", amount: summary.expenseMinorUnits, other: summary.incomeMinorUnits, color: theme.expense, identifier: "summary.expense")
                summaryBar("本月收入", amount: summary.incomeMinorUnits, other: summary.expenseMinorUnits, color: theme.income, identifier: "summary.income")
            }.padding(22).paperCard()
        } else { Text("本月汇总暂时无法计算，请检查账目金额。").foregroundStyle(theme.error) }
    }

    private func summaryBar(_ title: String, amount: Int64, other: Int64, color: Color, identifier: String) -> some View {
        HStack(spacing: 9) {
            Text(title).font(.system(size: 13)).foregroundStyle(theme.muted)
            GeometryReader { proxy in
                Capsule().fill(color.opacity(0.13))
                Capsule().fill(color).frame(width: proxy.size.width * (amount == 0 ? 0 : max(0.06, Double(amount) / max(Double(amount),Double(other),1))))
            }.frame(height: 11)
            Text("¥\(LedgerAmount.format(minorUnits: amount))").font(.system(size: 14,weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityIdentifier(identifier)
        }
    }

    private func dayHeading(_ day: Date) -> some View {
        HStack(spacing: 7) {
            Capsule().fill(theme.primary).frame(width: 3,height: 16)
            Text(day, format: .dateTime.month(.twoDigits).day(.twoDigits).weekday(.wide)).font(.system(size: 13,weight: .medium))
            Spacer()
            if let summary = try? model.daySummary(day) {
                Text("结余 ¥\(LedgerAmount.format(minorUnits: summary.balanceMinorUnits))").font(.system(size: 12)).foregroundStyle(theme.muted)
            }
        }.padding(.bottom, 5)
    }

    private func entryRow(_ entry: LedgerEntry) -> some View {
        Button { onSelect(entry) } label: {
            HStack(spacing: 12) {
                CategoryBadge(name: model.categoryName(entry.categoryID), size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.categoryName(entry.categoryID)).font(.system(size: 16,weight: .semibold))
                    if !entry.note.isEmpty { Text(entry.note).font(.system(size: 12)).foregroundStyle(theme.muted).lineLimit(2) }
                }
                Spacer(minLength: 8)
                Text("\(entry.kind == .expense ? "−" : "+") ¥\(entry.amount.decimalString)")
                    .font(.system(size: 17,weight: .semibold,design: .rounded)).monospacedDigit()
                    .foregroundStyle(entry.kind == .income ? theme.income : theme.ink)
            }.padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("entry.row.\(entry.id.uuidString)")
            .accessibilityLabel("\(model.categoryName(entry.categoryID))，\(entry.kind.title)，\(entry.amount.decimalString)元，\(entry.note)")
    }
}

@MainActor
private struct LedgerCalendarView: View {
    @Environment(\.ledgerTheme) private var theme
    let model: LedgerAppModel
    private var calendar: Calendar { Calendar.current }
    private var dates: [Date?] {
        guard let range = try? LedgerDateRanges.range(for: .month, containing: model.displayedMonth),
              let count = calendar.range(of: .day, in: .month, for: range.start) else { return [] }
        let padding = (calendar.component(.weekday, from: range.start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: padding) + count.map { calendar.date(byAdding: .day, value: $0 - 1, to: range.start) }
    }
    var body: some View {
        VStack(spacing: 13) {
            HStack {
                Button { model.moveMonth(by: -1) } label: { Image(systemName: "chevron.left").frame(width: 30,height: 30) }.accessibilityIdentifier("month.previous")
                Spacer()
                MonthPickerButton(displayedMonth: model.displayedMonth) { model.selectMonth($0) }
                Spacer()
                Button { model.moveMonth(by: 1) } label: { Image(systemName: "chevron.right").frame(width: 30,height: 30) }.accessibilityIdentifier("month.next")
            }.buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(),spacing: 3),count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]).font(.system(size: 11)).foregroundStyle(theme.muted).frame(height: 20)
                }
                ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                    if let date { dayButton(date) } else { Color.clear.frame(height: 42) }
                }
            }
            DashedRule()
            if let summary = try? model.selectedDay.map({ try model.daySummary($0) }) ?? model.monthSummary() {
                HStack {
                    Text(model.selectedDay == nil ? "本月收入" : "当日收入") + Text(" ¥\(LedgerAmount.format(minorUnits: summary.incomeMinorUnits))").foregroundColor(theme.income)
                    Spacer(minLength: 3)
                    Text(model.selectedDay == nil ? "本月支出" : "当日支出") + Text(" ¥\(LedgerAmount.format(minorUnits: summary.expenseMinorUnits))").foregroundColor(theme.expense)
                }.font(.system(size: 10,weight: .medium)).minimumScaleFactor(0.6).lineLimit(1)
            }
            if model.selectedDay != nil {
                Button("查看整月") { if let day = model.selectedDay { model.selectDay(day) } }.font(.caption).accessibilityIdentifier("calendar.clear-selection")
            }
        }.padding(15).paperCard()
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = model.selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let summary = try? model.daySummary(date)
        return Button { model.selectDay(date) } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))").font(.system(size: 12,weight: .medium))
                if let summary, summary.entryCount > 0 {
                    Text(LedgerAmount.format(minorUnits: summary.balanceMinorUnits)).font(.system(size: 7)).lineLimit(1).minimumScaleFactor(0.5)
                } else { Text(" ").font(.system(size: 7)) }
            }.frame(maxWidth: .infinity).frame(height: 42)
                .background(selected ? theme.primary : calendar.isDateInToday(date) ? theme.primarySoft : theme.calendarIdle, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(selected ? theme.onPrimary : theme.ink)
        }.buttonStyle(.plain).accessibilityLabel(date.formatted(.dateTime.year().month().day()))
            .accessibilityIdentifier("calendar.day.\(calendar.component(.day, from: date))")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

@MainActor
private struct LedgerBooksView: View {
    @Environment(\.ledgerTheme) private var theme
    let model: LedgerAppModel
    @State private var createsBook = false
    @State private var editingBook: LedgerBook?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                HStack { Text("我的账本").font(.system(size: 23,weight: .bold)); Spacer(); Text("\(model.books.count) 本").font(.caption).foregroundStyle(theme.muted) }
                ForEach(model.books) { book in
                    HStack(spacing: 12) {
                        Button { model.selectBook(book.id) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "book.closed").font(.system(size: 27,weight: .light)).frame(width: 53,height: 62).paperCard(fill: theme.primarySoft,radius: 5)
                                VStack(alignment: .leading,spacing: 8) {
                                    Text(book.name).font(.system(size: 16,weight: .semibold))
                                    Text(book.id == model.selectedBookID ? "正在使用" : "点击切换").font(.caption).foregroundStyle(theme.muted)
                                }
                                Spacer()
                                if book.id == model.selectedBookID { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.primary) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("book.select.\(book.id.uuidString)").accessibilityLabel(book.name)
                        Button { editingBook = book } label: { Image(systemName: "pencil").padding(9) }.buttonStyle(.plain)
                            .accessibilityLabel("重命名\(book.name)").accessibilityIdentifier("book.rename.\(book.id.uuidString)")
                    }.padding(16).paperCard()
                }
                Button { createsBook = true } label: { Label("新建账本",systemImage: "plus") }.buttonStyle(PaperButtonStyle(fill: theme.primarySoft)).accessibilityIdentifier("book.add")
            }.padding(22).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.disabled(model.isSaving)
            .sheet(isPresented: $createsBook) { BookEditorView(model: model) }
            .sheet(item: $editingBook) { BookEditorView(model: model, book: $0) }
    }
}

private struct LedgerProfileView: View {
    @Environment(\.ledgerTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("我的").font(.system(size: 23,weight: .bold))
                HStack(spacing: 18) {
                    Image(systemName: "book.pages").font(.system(size: 34,weight: .light)).frame(width: 70,height: 70).background(theme.primarySoft,in: Circle()).overlay { Circle().stroke(theme.ink,lineWidth: 1.5) }
                    VStack(alignment: .leading,spacing: 6) { Text("有落").font(.title2.bold()); Text("把生活，一笔笔留下").font(.caption).foregroundStyle(theme.muted) }
                }.padding(.vertical, 12)
                VStack(alignment: .leading,spacing: 18) {
                    Label("本地账本", systemImage: "internaldrive").font(.headline)
                    DashedRule()
                    Text("数据保存在本机，未启用 iCloud 同步。").font(.system(size: 14)).lineSpacing(5).accessibilityIdentifier("settings.local-data")
                }.padding(21).frame(maxWidth: .infinity,alignment: .leading).paperCard()
                Text("有落 · YoloLedger").font(.caption).foregroundStyle(theme.muted).frame(maxWidth: .infinity).padding(.top, 15)
            }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
    }
}
