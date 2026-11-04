#if os(iOS)
import SwiftUI
import YoloLedgerCore

@MainActor
struct LedgerScheduledEntryView: View {
    @Environment(\.ledgerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let controller: LedgerScheduledEntryController
    let books: [LedgerBook]
    let categories: [LedgerCategory]
    @State private var editor: EditorContext?
    @State private var pendingDeletion: LedgerScheduledEntryRule?
    @State private var togglingRuleID: UUID?
    @State private var transitionNotice: ScheduledEntryTransitionNotice?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        timingNotice
                        if controller.isLoading && controller.rules.isEmpty {
                            ProgressView("正在读取规则")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 44)
                        } else if let error = controller.loadError, controller.rules.isEmpty {
                            errorCard(error)
                        } else if controller.rules.isEmpty {
                            emptyCard
                        } else {
                            groupHeader(
                                title: "正在执行",
                                count: enabledRules.count,
                                systemImage: "play.circle.fill",
                                color: theme.primary
                            )
                            .id(ScheduledEntryRuleGroup.enabled.anchorID)
                            .accessibilityIdentifier("scheduled-entry.group.enabled")
                            if enabledRules.isEmpty {
                                groupEmptyMessage("暂无正在执行的规则")
                            } else {
                                ForEach(enabledRules) { rule in ruleCard(rule) }
                            }

                            groupHeader(
                                title: "已暂停",
                                count: pausedRules.count,
                                systemImage: "pause.circle.fill",
                                color: theme.muted
                            )
                            .id(ScheduledEntryRuleGroup.paused.anchorID)
                            .accessibilityIdentifier("scheduled-entry.group.paused")
                            if pausedRules.isEmpty {
                                groupEmptyMessage("暂无已暂停的规则")
                            } else {
                                ForEach(pausedRules) { rule in ruleCard(rule) }
                            }
                        }
                        if let error = controller.operationError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(theme.error)
                                .accessibilityIdentifier("scheduled-entry.operation-error")
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                    .animation(.snappy(duration: 0.28), value: enabledRules.map(\.id))
                    .animation(.snappy(duration: 0.28), value: pausedRules.map(\.id))
                }
                .background(PaperBackground())
                .refreshable { await controller.load() }
                .overlay(alignment: .top) { transitionBanner(proxy: proxy) }
            }
            .navigationTitle("定时记账")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { controller.dismissList(); dismiss() }
                        .disabled(controller.isSaving)
                        .accessibilityIdentifier("scheduled-entry.done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editor = EditorContext(rule: nil) } label: {
                        Label("新建", systemImage: "plus")
                    }
                    .disabled(books.isEmpty || categories.isEmpty || controller.isSaving)
                    .accessibilityIdentifier("scheduled-entry.add")
                }
            }
            .task { await controller.load() }
            .sheet(item: $editor) { context in
                LedgerScheduledEntryEditorView(
                    controller: controller,
                    books: books,
                    categories: categories,
                    rule: context.rule
                )
            }
            .confirmationDialog(
                "删除这条定时记账规则？",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除规则", role: .destructive) {
                    guard let rule = pendingDeletion else { return }
                    pendingDeletion = nil
                    Task { _ = await controller.delete(rule) }
                }
                .accessibilityIdentifier("scheduled-entry.delete.confirm")
                Button("取消", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("已经自动生成的账目会保留；这条规则以后不再生成新账目。")
            }
        }
        .interactiveDismissDisabled(controller.isSaving)
    }

    private var enabledRules: [LedgerScheduledEntryRule] {
        controller.rules.filter(\.isEnabled)
    }

    private var pausedRules: [LedgerScheduledEntryRule] {
        controller.rules.filter { !$0.isEnabled }
    }

    private var timingNotice: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("自动补记说明", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.headline)
            Text("iOS 后台刷新由系统决定时机，不能保证在当天的精确时刻执行。若后台没有及时运行，下次打开\(YoloLedgerProduct.displayName)时会自动补记。")
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(theme.muted)
        }
        .padding(17)
        .paperCard(fill: theme.primarySoft)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scheduled-entry.timing")
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 36, weight: .light))
            Text("还没有定时记账").font(.headline)
            Text("可按每月固定日期或最后一天，自动生成一笔收入或支出。")
                .font(.caption)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
            Button("新建规则") { editor = EditorContext(rule: nil) }
                .buttonStyle(PaperButtonStyle(fill: theme.primarySoft))
                .accessibilityIdentifier("scheduled-entry.empty-add")
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .paperCard()
        .accessibilityIdentifier("scheduled-entry.empty")
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.error)
            Button("重试") { Task { await controller.load() } }
                .buttonStyle(PaperButtonStyle(fill: theme.primarySoft))
        }
        .padding(18)
        .paperCard()
        .accessibilityIdentifier("scheduled-entry.load-error")
    }

    private func groupHeader(
        title: String,
        count: Int,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
            Spacer()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func groupEmptyMessage(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func transitionBanner(proxy: ScrollViewProxy) -> some View {
        if let notice = transitionNotice {
            HStack(spacing: 10) {
                Image(systemName: notice.target == .enabled ? "play.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(notice.target == .enabled ? theme.primary : theme.muted)
                Text(notice.message)
                    .font(.caption)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("查看") {
                    withAnimation(.snappy) {
                        proxy.scrollTo(notice.target.anchorID, anchor: .top)
                        transitionNotice = nil
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(theme.primary)
                .accessibilityIdentifier("scheduled-entry.transition.view")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.ink, lineWidth: 1.2)
            }
            .shadow(color: theme.shadow, radius: 8, y: 3)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func ruleCard(_ rule: LedgerScheduledEntryRule) -> some View {
        let cardInk = rule.isEnabled ? theme.ink : theme.muted
        let cardFill = rule.isEnabled ? theme.surface : theme.calendarIdle

        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(rule.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? categoryName(rule.categoryID) : rule.note)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(cardInk)
                    Text("\(bookName(rule.bookID)) · \(categoryName(rule.categoryID))")
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                }
                Spacer()
                Text("¥\(rule.amount.decimalString)")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(cardInk)
            }
            DashedRule().opacity(rule.isEnabled ? 1 : 0.45)
            HStack {
                Label(rule.kind.title, systemImage: rule.kind == .expense ? "arrow.up.right" : "arrow.down.left")
                Spacer()
                Text(scheduleText(rule.monthlyDay))
            }
            .font(.caption)
            .foregroundStyle(cardInk)
            Label(
                rule.isEnabled ? "将按计划自动记账" : "暂停期间不会自动记账",
                systemImage: rule.isEnabled ? "calendar.badge.checkmark" : "calendar.badge.exclamationmark"
            )
            .font(.caption)
            .foregroundStyle(rule.isEnabled ? theme.primary : theme.muted)
            .accessibilityIdentifier("scheduled-entry.status-detail.\(rule.id.uuidString)")
            HStack(spacing: 10) {
                Button("编辑") { editor = EditorContext(rule: rule) }
                    .buttonStyle(PaperButtonStyle())
                    .accessibilityIdentifier("scheduled-entry.edit.\(rule.id.uuidString)")
                Button {
                    togglingRuleID = rule.id
                    Task {
                        let succeeded = await controller.setEnabled(!rule.isEnabled, for: rule)
                        togglingRuleID = nil
                        if succeeded { showTransitionNotice(for: rule) }
                    }
                } label: {
                    if togglingRuleID == rule.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(rule.isEnabled ? "暂停" : "恢复启用")
                    }
                }
                .buttonStyle(PaperButtonStyle(fill: rule.isEnabled ? theme.surface : theme.primarySoft))
                .accessibilityIdentifier("scheduled-entry.toggle.\(rule.id.uuidString)")
                Button(role: .destructive) { pendingDeletion = rule } label: {
                    Image(systemName: "trash").frame(width: 32)
                }
                .buttonStyle(PaperButtonStyle())
                .accessibilityLabel("删除规则")
                .accessibilityIdentifier("scheduled-entry.delete.\(rule.id.uuidString)")
            }
        }
        .padding(17)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(rule.isEnabled ? theme.ink : theme.muted.opacity(0.7), lineWidth: rule.isEnabled ? 1.5 : 1.2)
        }
        .disabled(controller.isSaving)
        .id("scheduled-entry-rule-\(rule.id.uuidString)-\(rule.isEnabled)")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scheduled-entry.rule.\(rule.id.uuidString)")
    }

    private func showTransitionNotice(for rule: LedgerScheduledEntryRule) {
        let target: ScheduledEntryRuleGroup = rule.isEnabled ? .paused : .enabled
        let action = rule.isEnabled ? "已暂停" : "已恢复"
        let targetName = rule.isEnabled ? "已暂停" : "正在执行"
        let notice = ScheduledEntryTransitionNotice(
            message: "“\(ruleTitle(rule))”\(action)，已移至「\(targetName)」",
            target: target
        )
        withAnimation(.snappy) { transitionNotice = notice }
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard transitionNotice?.id == notice.id else { return }
            withAnimation(.easeOut(duration: 0.2)) { transitionNotice = nil }
        }
    }

    private func ruleTitle(_ rule: LedgerScheduledEntryRule) -> String {
        let note = rule.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? categoryName(rule.categoryID) : note
    }

    private func bookName(_ id: UUID) -> String { books.first { $0.id == id }?.name ?? "未找到账本" }
    private func categoryName(_ id: UUID) -> String { categories.first { $0.id == id }?.name ?? "未找到分类" }
    private func scheduleText(_ value: LedgerMonthlyDay) -> String {
        switch value {
        case let .fixed(day): "每月 \(day) 日"
        case .lastDay: "每月最后一天"
        }
    }
}

private enum ScheduledEntryRuleGroup: Equatable {
    case enabled
    case paused

    var anchorID: String {
        switch self {
        case .enabled: "scheduled-entry-group-enabled-anchor"
        case .paused: "scheduled-entry-group-paused-anchor"
        }
    }
}

private struct ScheduledEntryTransitionNotice: Identifiable {
    let id = UUID()
    let message: String
    let target: ScheduledEntryRuleGroup
}

private struct EditorContext: Identifiable {
    let id = UUID()
    let rule: LedgerScheduledEntryRule?
}

@MainActor
private struct LedgerScheduledEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ledgerTheme) private var theme
    let controller: LedgerScheduledEntryController
    let books: [LedgerBook]
    let categories: [LedgerCategory]
    let rule: LedgerScheduledEntryRule?
    @State private var bookID: UUID?
    @State private var kind: LedgerEntryKind
    @State private var categoryID: UUID?
    @State private var amountText: String
    @State private var note: String
    @State private var monthlyDayValue: Int
    @State private var effectiveDate: Date
    @State private var validationMessage: String?

    init(
        controller: LedgerScheduledEntryController,
        books: [LedgerBook],
        categories: [LedgerCategory],
        rule: LedgerScheduledEntryRule?
    ) {
        self.controller = controller
        self.books = books
        self.categories = categories
        self.rule = rule
        let initialKind = rule?.kind ?? .expense
        _bookID = State(initialValue: rule?.bookID ?? books.first?.id)
        _kind = State(initialValue: initialKind)
        _categoryID = State(initialValue: rule?.categoryID ?? categories.first { $0.kind == initialKind }?.id)
        _amountText = State(initialValue: rule?.amount.decimalString ?? "")
        _note = State(initialValue: rule?.note ?? "")
        let initialMonthlyDayValue = switch rule?.monthlyDay ?? .fixed(1) {
        case let .fixed(day): day
        case .lastDay: 0
        }
        _monthlyDayValue = State(initialValue: initialMonthlyDayValue)
        let now = Date()
        let calendar = Self.localGregorianCalendar
        let currentMonth = try? LedgerYearMonth.containing(
            now,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        let initialMonth = currentMonth.map {
            LedgerScheduledEntryMonthPolicy.clampedToCurrentMonth(
                ruleMonth: rule?.effectiveStartMonth,
                currentMonth: $0
            )
        }
        _effectiveDate = State(initialValue: Self.date(for: initialMonth) ?? now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账目") {
                    Picker("账本", selection: $bookID) {
                        ForEach(books) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .accessibilityIdentifier("scheduled-entry.editor.book")
                    Picker("类型", selection: $kind) {
                        Text("支出").tag(LedgerEntryKind.expense)
                        Text("收入").tag(LedgerEntryKind.income)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("scheduled-entry.editor.kind")
                    Picker("分类", selection: $categoryID) {
                        ForEach(filteredCategories) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .accessibilityIdentifier("scheduled-entry.editor.category")
                    TextField("金额", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("scheduled-entry.editor.amount")
                    TextField("备注（可选）", text: $note)
                        .accessibilityIdentifier("scheduled-entry.editor.note")
                }

                Section("每月执行") {
                    Picker("日期", selection: $monthlyDayValue) {
                        Text("最后一天").tag(0)
                        ForEach(1...31, id: \.self) { Text("\($0) 日").tag($0) }
                    }
                    .accessibilityIdentifier("scheduled-entry.editor.day")
                    if rule == nil {
                        LabeledContent("生效月份", value: currentMonthText)
                    } else {
                        DatePicker(
                            "生效月份",
                            selection: $effectiveDate,
                            in: currentMonthStart...,
                            displayedComponents: .date
                        )
                        .accessibilityIdentifier("scheduled-entry.editor.effective-month")
                    }
                    Text(rule == nil ? "新规则从当前本地月份生效。" : "只影响所选月份及之后的未来账目，已经生成的账目不会改变。")
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                        .accessibilityIdentifier("scheduled-entry.editor.future-only")
                }

                if let message = validationMessage ?? controller.operationError {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.error)
                            .accessibilityIdentifier("scheduled-entry.editor.error")
                    }
                }
            }
            .navigationTitle(rule == nil ? "新建定时记账" : "编辑定时记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(controller.isSaving)
                        .accessibilityIdentifier("scheduled-entry.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(controller.isSaving ? "保存中" : "保存") { Task { await save() } }
                        .disabled(controller.isSaving)
                        .accessibilityIdentifier("scheduled-entry.editor.save")
                }
            }
            .interactiveDismissDisabled(controller.isSaving)
            .onChange(of: kind) { _, newKind in
                if !categories.contains(where: { $0.id == categoryID && $0.kind == newKind }) {
                    categoryID = categories.first { $0.kind == newKind }?.id
                }
            }
        }
    }

    private var filteredCategories: [LedgerCategory] { categories.filter { $0.kind == kind } }

    private var currentMonthStart: Date {
        let calendar = localCalendar
        let components = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: components) ?? Date()
    }

    private var currentMonthText: String { currentMonthStart.formatted(.dateTime.year().month(.wide)) }

    private var localCalendar: Calendar {
        Self.localGregorianCalendar
    }

    private func save() async {
        do {
            guard let bookID else { validationMessage = "请选择账本。"; return }
            guard let categoryID,
                  categories.contains(where: { $0.id == categoryID && $0.kind == kind })
            else { validationMessage = "请选择与收支类型匹配的分类。"; return }
            let amount = try LedgerAmount(input: amountText)
            let now = Date()
            let effectiveStartMonth = try LedgerYearMonth.containing(
                rule == nil ? now : effectiveDate,
                calendar: localCalendar,
                timeZone: .current
            )
            let currentMonth = try LedgerYearMonth.containing(now, calendar: localCalendar, timeZone: .current)
            guard effectiveStartMonth >= currentMonth else {
                validationMessage = "生效月份不能早于当前月份。"
                return
            }
            let saved = try LedgerScheduledEntryRule(
                id: rule?.id ?? UUID(),
                bookID: bookID,
                categoryID: categoryID,
                kind: kind,
                amount: amount,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                monthlyDay: monthlyDayValue == 0 ? .lastDay : .fixed(monthlyDayValue),
                isEnabled: rule?.isEnabled ?? true,
                effectiveStartMonth: effectiveStartMonth,
                createdAt: rule?.createdAt ?? now,
                updatedAt: now
            )
            validationMessage = nil
            if await controller.save(saved) { dismiss() }
        } catch {
            validationMessage = (error as? any LocalizedError)?.errorDescription ?? "请检查填写内容。"
        }
    }

    private static func date(for month: LedgerYearMonth?) -> Date? {
        guard let month else { return nil }
        return localGregorianCalendar.date(
            from: DateComponents(year: month.year, month: month.month, day: 1, hour: 12)
        )
    }

    private static var localGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}
#endif
