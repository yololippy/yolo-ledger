import SwiftUI
import YoloLedgerCore

@MainActor
struct EntryDetailView: View {
    let model: LedgerAppModel
    let entryID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ledgerTheme) private var theme
    @State private var isEditing = false
    @State private var confirmsDelete = false
    @State private var errorMessage: String?
    private var entry: LedgerEntry? { model.entries.first { $0.id == entryID } }

    var body: some View {
        ZStack {
            theme.detailBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("完成") { dismiss() }.accessibilityIdentifier("detail.close")
                    Spacer(); Text("账目小票").font(.headline); Spacer()
                    Button("编辑") { isEditing = true }.accessibilityIdentifier("entry.edit").disabled(entry == nil)
                }.font(.system(size: 15,weight: .medium)).padding(20)
                ScrollView {
                    if let entry { receipt(entry).id(entry.updatedAt) }
                    else { Text("账目已不存在").padding(30) }
                    if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(theme.error).padding().accessibilityIdentifier("detail.error") }
                    Button("删除这笔账目",role: .destructive) { confirmsDelete = true }.font(.system(size: 14)).padding(20).accessibilityIdentifier("entry.delete").disabled(model.isSaving)
                }
            }
        }.foregroundStyle(theme.ink).font(.system(.body,design: .rounded)).tint(theme.ink).buttonStyle(.plain)
            #if os(iOS)
            .fullScreenCover(isPresented: $isEditing) { if let entry { EntryEditorView(model: model,entry: entry) } }
            #else
            .sheet(isPresented: $isEditing) { if let entry { EntryEditorView(model: model,entry: entry) } }
            #endif
            .confirmationDialog("删除这笔账目？",isPresented: $confirmsDelete,titleVisibility: .visible) {
                Button("删除账目",role: .destructive) {
                    Task { if await model.deleteEntry(entryID) { dismiss() } else { errorMessage = model.operationError } }
                }.accessibilityIdentifier("entry.delete.confirm")
                Button("取消",role: .cancel) {}
            } message: { Text("删除后无法撤销。") }
            .interactiveDismissDisabled(model.isSaving)
            #if os(macOS)
            .frame(width: 480,height: 680)
            #endif
    }

    private func receipt(_ entry: LedgerEntry) -> some View {
        VStack(spacing: 23) {
            VStack(spacing: 7) {
                Text("有 落").font(.system(size: 30,weight: .heavy,design: .rounded))
                Text("生活记账单").font(.system(size: 16,weight: .semibold))
                Text("YOLO LEDGER").font(.system(size: 9,weight: .medium,design: .monospaced)).tracking(3)
            }.padding(.top,15)
            DashedRule()
            Text(model.bookName(entry.bookID)).font(.system(size: 18,weight: .bold))
            DashedRule()
            HStack { Text("记账日期"); Spacer(); Text(entry.date,format: .dateTime.year().month(.twoDigits).day(.twoDigits)) }.font(.system(size: 13))
            HStack(spacing: 13) {
                CategoryBadge(name: model.categoryName(entry.categoryID),size: 52)
                VStack(alignment: .leading,spacing: 5) { Text(model.categoryName(entry.categoryID)).font(.headline); Text(entry.kind.title).font(.caption).foregroundStyle(theme.muted) }
                Spacer()
                Text("¥\(entry.amount.decimalString)").font(.system(size: 19,weight: .semibold,design: .rounded)).accessibilityIdentifier("detail.amount")
            }.padding(.vertical,8)
            VStack(alignment: .leading,spacing: 9) {
                Text("备注").font(.caption).foregroundStyle(theme.muted)
                Text(entry.note.isEmpty ? "无" : entry.note).font(.system(size: 14)).textSelection(.enabled).accessibilityIdentifier("detail.note")
            }.frame(maxWidth: .infinity,alignment: .leading)
            DashedRule()
            HStack {
                Text(entry.kind == .expense ? "本笔支出" : "本笔收入").font(.system(size: 15,weight: .semibold))
                Spacer()
                Text("¥ \(entry.amount.decimalString)").font(.system(size: 22,weight: .semibold,design: .rounded))
            }.foregroundStyle(entry.kind == .expense ? theme.expense : theme.income)
            Text("认真记下每一笔 · 好好过好每一天").font(.system(size: 10)).foregroundStyle(theme.muted).padding(.bottom,14)
        }.padding(24).background(theme.surface,in: ReceiptShape()).overlay { ReceiptShape().stroke(theme.ink,lineWidth: 1.5) }
            .padding(.horizontal,22).padding(.top,10)
    }
}

private struct ReceiptShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0,y: 0)); path.addLine(to: CGPoint(x: rect.maxX,y: 0)); path.addLine(to: CGPoint(x: rect.maxX,y: rect.maxY - 8))
        let steps = max(1,Int(rect.width / 14)); let step = rect.width / CGFloat(steps)
        for index in (0..<steps).reversed() {
            path.addLine(to: CGPoint(x: CGFloat(index) * step + step / 2,y: rect.maxY))
            path.addLine(to: CGPoint(x: CGFloat(index) * step,y: rect.maxY - 8))
        }
        path.closeSubpath(); return path
    }
}
