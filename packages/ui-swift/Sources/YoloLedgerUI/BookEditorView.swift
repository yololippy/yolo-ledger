import SwiftUI
import YoloLedgerCore

@MainActor
struct BookEditorView: View {
    let model: LedgerAppModel
    let book: LedgerBook?
    @State private var name: String
    @State private var creationID = UUID()
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ledgerTheme) private var theme
    init(model: LedgerAppModel, book: LedgerBook? = nil) {
        self.model = model; self.book = book; _name = State(initialValue: book?.name ?? "")
    }
    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 25) {
                HStack { Button("取消") { dismiss() }; Spacer(); Text(book == nil ? "新建账本" : "重命名账本").font(.headline); Spacer(); Text("取消").hidden() }.font(.system(size: 14)).padding(.bottom, 12)
                Image(systemName: "book.closed").font(.system(size: 42,weight: .light)).frame(width: 82,height: 98).paperCard(fill: theme.primarySoft,radius: 7)
                TextField("账本名称",text: $name).textFieldStyle(.plain).font(.system(size: 18)).padding(17).paperCard().accessibilityIdentifier("book-editor.name")
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(theme.error).accessibilityIdentifier("book-editor.error") }
                Button(model.isSaving ? "保存中" : "保存账本") {
                    Task {
                        if await model.saveBook(name: name,editingID: book?.id,creationID: creationID) { dismiss() }
                        else { errorMessage = model.operationError }
                    }
                }.buttonStyle(PaperButtonStyle(fill: theme.primarySoft)).accessibilityIdentifier("book-editor.save").keyboardShortcut(.defaultAction)
                Spacer(minLength: 0)
            }.padding(25).disabled(model.isSaving)
        }.foregroundStyle(theme.ink).tint(theme.ink).interactiveDismissDisabled(model.isSaving)
        #if os(macOS)
        .frame(width: 420,height: 400)
        #endif
    }
}
