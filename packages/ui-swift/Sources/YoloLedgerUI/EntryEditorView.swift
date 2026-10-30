import SwiftUI
import YoloLedgerCore

@MainActor
struct EntryEditorView: View {
    let model: LedgerAppModel
    let entry: LedgerEntry?
    let proposal: LedgerScreenshotProposal?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ledgerTheme) private var theme
    @State private var kind: LedgerEntryKind
    @State private var amountText: String
    @State private var categoryID: UUID?
    @State private var bookID: UUID?
    @State private var date: Date
    @State private var note: String
    @State private var source: LedgerEntrySource
    @State private var creationID = UUID()
    @State private var errorMessage: String?
    @State private var showsDate = false
    @FocusState private var noteFocused: Bool

    init(
        model: LedgerAppModel,
        entry: LedgerEntry? = nil,
        proposal: LedgerScreenshotProposal? = nil,
        initialDate: Date? = nil
    ) {
        self.model = model; self.entry = entry; self.proposal = proposal
        let kind = entry?.kind ?? proposal?.kind ?? .expense
        _kind = State(initialValue: kind)
        _amountText = State(initialValue: entry?.amount.decimalString ?? proposal?.amountMinorUnits.map(LedgerAmount.format) ?? "")
        _categoryID = State(initialValue: entry?.categoryID ?? model.categories.first {
            $0.kind == kind && $0.name == proposal?.suggestedCategoryName
        }?.id ?? model.categories.first { $0.kind == kind }?.id)
        _bookID = State(initialValue: entry?.bookID ?? model.selectedBookID)
        _date = State(initialValue: entry?.date ?? proposal?.transactionDate ?? initialDate ?? Date())
        _note = State(initialValue: entry?.note ?? proposal?.merchant ?? "")
        _source = State(initialValue: entry?.source ?? (proposal == nil ? .manual : .screenshotShortcut))
        if proposal?.amountMinorUnits == 0 {
            _errorMessage = State(initialValue: "识别到实付款为 0，本次没有实际支出；如仍需记账，请修改金额后保存。")
        } else {
            _errorMessage = State(initialValue: proposal != nil && proposal?.amount == nil ? "没有识别到明确金额，请手动输入并核对。" : nil)
        }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                header
                HStack(spacing: 40) {
                    kindButton(.expense); kindButton(.income)
                }.padding(.top, 16).padding(.bottom, 25)
                categoryPicker
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(theme.error).frame(maxWidth: .infinity,alignment: .leading).padding(.horizontal,18).padding(.vertical,8).accessibilityIdentifier("editor.error")
                }
                inputPanel
            }.disabled(model.isSaving)
        }
        .foregroundStyle(theme.ink).font(.system(.body,design: .rounded)).tint(theme.primary)
        .interactiveDismissDisabled(model.isSaving)
        .onChange(of: kind) { _, value in
            if !model.categories.contains(where: { $0.id == categoryID && $0.kind == value }) { categoryID = model.categories.first { $0.kind == value }?.id }
        }
        .popover(isPresented: $showsDate) {
            VStack(spacing: 16) {
                Text("记账日期").font(.headline)
                DatePicker("日期",selection: $date,displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().accessibilityIdentifier("editor.date")
                Button("确定") { showsDate = false }.buttonStyle(PaperButtonStyle(fill: theme.primarySoft))
            }.padding(20).frame(minWidth: 300).presentationCompactAdaptation(.sheet)
        }
        #if os(macOS)
        .frame(width: 500,height: 700)
        #endif
    }

    private var categoryPicker: some View {
        GeometryReader { geometry in
            // Keep four columns within the actual viewport; 70 pt is the upper bound.
            let diameter = min(70, max(1, (geometry.size.width - 44 - 3 * 13) / 4))
            let scale = diameter / 70
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(),spacing: 13),count: 4),spacing: 14) {
                    ForEach(model.categories.filter { $0.kind == kind }) { category in
                        Button { categoryID = category.id; noteFocused = false } label: {
                            VStack(spacing: 0) {
                                CategoryIllustration(name: category.name, size: 32 * scale).padding(.top, 9 * scale)
                                Text(category.name).font(.system(size: 12 * scale,weight: .medium))
                                    .padding(.top, 3 * scale).padding(.bottom, 9 * scale)
                            }.frame(width: diameter,height: diameter)
                                .background(theme.surface,in: Circle())
                                .overlay { Circle().stroke(categoryID == category.id ? theme.primary : theme.ink,lineWidth: categoryID == category.id ? 2.5 : 1.4) }
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).accessibilityIdentifier("editor.category.\(category.id.uuidString)")
                            .accessibilityLabel(category.name).accessibilityAddTraits(categoryID == category.id ? .isSelected : [])
                    }
                }.padding(.horizontal,22).padding(.top, 4).padding(.bottom, 20)
            }.id(kind).accessibilityIdentifier("editor.categories")
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 20)).frame(width: 36,height: 36) }
                .accessibilityIdentifier("editor.cancel").accessibilityLabel("取消")
            Spacer()
            Text(proposal != nil ? "确认截图记账" : entry == nil ? "记一笔" : "编辑账目")
                .font(.system(size: 16,weight: .semibold))
                .accessibilityIdentifier(proposal == nil ? "editor.title" : "editor.screenshot-confirmation")
            Spacer()
            Menu {
                ForEach(model.books) { book in
                    Button(book.name) { bookID = book.id }.accessibilityIdentifier("editor.book.option.\(book.id.uuidString)")
                }
            } label: {
                HStack(spacing: 4) { Text(model.books.first { $0.id == bookID }?.name ?? "账本").font(.system(size: 12)); Image(systemName: "book.closed").font(.system(size: 17)) }
                    .lineLimit(1).frame(maxWidth: 116)
            }.accessibilityIdentifier("editor.book")
        }.buttonStyle(.plain).padding(.horizontal,14).padding(.top,8)
    }

    private func kindButton(_ value: LedgerEntryKind) -> some View {
        Button { kind = value; noteFocused = false } label: {
            Text(value.title).font(.system(size: 21,weight: kind == value ? .bold : .regular))
                .foregroundStyle(kind == value ? theme.ink : theme.muted)
                .padding(.horizontal,6).padding(.bottom,9)
                .overlay(alignment: .bottom) { if kind == value { Capsule().fill(theme.primary).frame(height: 3).rotationEffect(.degrees(-3)) } }
        }.buttonStyle(.plain).accessibilityIdentifier("editor.kind.\(value.rawValue)")
            .accessibilityAddTraits(kind == value ? .isSelected : [])
    }

    private var inputPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "pencil.line").font(.system(size: 19)).frame(width: 30)
                HStack(spacing: 6) {
                    TextField("点击输入备注…",text: $note).textFieldStyle(.plain).font(.system(size: 13)).focused($noteFocused).submitLabel(.done).onSubmit { noteFocused = false }.accessibilityIdentifier("editor.note")
                    #if os(macOS)
                    TextField("0.00",text: $amountText).textFieldStyle(.plain).multilineTextAlignment(.trailing).font(.system(size: 25,design: .rounded)).frame(maxWidth: 210).accessibilityLabel("金额").accessibilityIdentifier("editor.amount")
                    #else
                    Button { noteFocused = false } label: {
                        Text("¥\(amountText.isEmpty ? "0.00" : amountText)").font(.system(size: 27,weight: .regular,design: .rounded)).lineLimit(1).minimumScaleFactor(0.4).frame(minWidth: 90,maxWidth: 180,alignment: .trailing)
                    }.buttonStyle(.plain).accessibilityIdentifier("editor.amount").accessibilityLabel("金额 \(amountText.isEmpty ? "0.00" : amountText)")
                    #endif
                }.padding(.horizontal,11).padding(.vertical,13).paperCard()
            }
            if hidesKeypad {
                Button("收起键盘，继续记账") { noteFocused = false }.font(.system(size: 13,weight: .medium)).frame(maxWidth: .infinity).padding(.vertical,10).accessibilityIdentifier("editor.keypad-return")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(),spacing: 10),count: 4),spacing: 9) {
                    ForEach(["7","8","9","date","4","5","6","+","1","2","3","-",".","0","delete","save"],id: \.self) { key in
                        keypadButton(key)
                    }
                }
            }
        }.padding(.horizontal,14).padding(.top,13).padding(.bottom,10)
            .background(keypadBackground.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(theme.ink).frame(height: 1.4) }
    }

    private var hidesKeypad: Bool {
        #if os(iOS)
        noteFocused
        #else
        false
        #endif
    }

    private var keypadBackground: Color { theme.keypadBackground }

    @ViewBuilder private func keypadButton(_ key: String) -> some View {
        let button = Button {
            if key == "save" { Task { await save() } }
            else if key == "date" { showsDate = true }
            else if key == "delete" { if !amountText.isEmpty { amountText.removeLast() }; errorMessage = nil }
            else if amountText.count < 42 { amountText += key; errorMessage = nil }
        } label: {
            Group {
                switch key {
                case "date":
                    VStack(spacing: 2) {
                        Image(systemName: "calendar").font(.system(size: 16))
                        Text(Calendar.current.isDateInToday(date) ? "今天" : date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))).font(.system(size: 12,weight: .semibold))
                    }
                case "delete": Image(systemName: "delete.left").font(.system(size: 23))
                case "save": Text(model.isSaving ? "保存中" : "完成").font(.system(size: 17,weight: .bold)).foregroundStyle(theme.onPrimary)
                default: Text(key == "-" ? "−" : key).font(.system(size: 28,weight: .regular,design: .rounded))
                }
            }.frame(maxWidth: .infinity).frame(height: 52)
                .paperCard(fill: key == "save" ? theme.accent : theme.surface,radius: 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.shadow).offset(y: 3))
        }.buttonStyle(.plain).accessibilityIdentifier(key == "save" ? "editor.save" : "keypad.\(key)")
            .accessibilityLabel(key == "save" ? "保存" : key == "delete" ? "退格" : key == "date" ? "选择日期" : key)
        if key == "save" { button.keyboardShortcut(.defaultAction) } else { button }
    }

    private func save() async {
        do {
            let amount = try LedgerAmountExpression.evaluate(amountText)
            guard let bookID else { errorMessage = "请选择账本。"; return }
            guard let categoryID else { errorMessage = "请选择分类。"; return }
            let draft = LedgerEntryDraft(bookID: bookID,categoryID: categoryID,kind: kind,amount: amount,date: date,note: note,source: source)
            if await model.saveEntry(draft,editingID: entry?.id,creationID: creationID) { dismiss() }
            else { errorMessage = model.operationError }
        } catch { errorMessage = LedgerAppModel.message(for: error) }
    }
}
