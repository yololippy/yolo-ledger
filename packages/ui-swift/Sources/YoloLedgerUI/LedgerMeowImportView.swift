import SwiftUI
import YoloLedgerCore

@MainActor
struct LedgerMeowImportView: View {
    @Environment(\.ledgerTheme) private var theme
    let controller: LedgerMeowImportController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if controller.isReadingFiles {
                        ProgressView("正在读取 CSV")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 50)
                    } else if let result = controller.result {
                        success(result)
                    } else if let selection = controller.selection {
                        preview(selection)
                    } else {
                        unavailable
                    }
                }
                .padding(22)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(PaperBackground())
            .foregroundStyle(theme.ink)
            .navigationTitle("从喵喵记账导入")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { controller.cancelReview() }
                        .disabled(controller.isImporting)
                        .accessibilityIdentifier("meow-import.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
        }
        .interactiveDismissDisabled(controller.isImporting)
        #if os(macOS)
        .frame(minWidth: 610, minHeight: 580)
        #endif
    }

    @ViewBuilder
    private func preview(_ selection: LedgerMeowImportSelection) -> some View {
        let preview = selection.preview
        VStack(alignment: .leading, spacing: 9) {
            Label("导入预览", systemImage: "doc.text.magnifyingglass")
                .font(.title3.bold())
            Text("已读取 \(preview.fileCount) 个 CSV；确认前不会写入本地账库。")
                .font(.subheadline)
                .foregroundStyle(theme.muted)
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
            metric("有效", "\(preview.validRecordCount) 笔", "checkmark.circle")
            metric("错误", "\(preview.invalidRowCount) 行", "exclamationmark.triangle")
            metric("重复内容", "\(preview.duplicateContentRecordCount) 笔", "doc.on.doc")
            metric("文件", "\(preview.fileCount) 个", "doc.on.doc")
            metric("账本", "\(preview.distinctBookCount) 个", "books.vertical")
            metric("分类", "\(preview.distinctCategoryCount) 个", "square.grid.2x2")
            metric("账户", "\(preview.distinctAccountCount) 个", "wallet.bifold")
            metric("货币", "\(preview.distinctCurrencyCount) 种", "yensign.circle")
        }
        .accessibilityIdentifier("meow-import.metrics")

        VStack(alignment: .leading, spacing: 13) {
            Text("收支汇总").font(.headline)
            DashedRule()
            summaryLine(
                title: "支出",
                count: preview.expenseRecordCount,
                minorUnits: preview.expenseTotalMinorUnits
            )
            summaryLine(
                title: "收入",
                count: preview.incomeRecordCount,
                minorUnits: preview.incomeTotalMinorUnits
            )
            HStack {
                Text("日期范围")
                Spacer()
                Text(dateRange(preview))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(17)
        .paperCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meow-import.summary")

        if !selection.issues.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("需要先修复 CSV", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(theme.error)
                Text("检测到错误时不会导入任何数据。下方只显示文件名、行号和错误类型，不展示原始账目内容。")
                    .font(.caption)
                    .foregroundStyle(theme.muted)
                ForEach(selection.issues) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.fileName).font(.caption.bold())
                        Text("第 \(issue.line) 行 · \(issue.description)")
                            .font(.system(size: 13))
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(17)
            .paperCard(fill: theme.surface, radius: 8)
            .accessibilityIdentifier("meow-import.issues")
        }

        VStack(alignment: .leading, spacing: 10) {
            Label("导入前保护", systemImage: "externaldrive.badge.checkmark")
                .font(.headline)
            Text("不会修改或删除喵喵记账中的数据。开始导入前，有落记账会先创建本地备份；导入失败时保持现有本地数据不变。")
                .font(.system(size: 14))
                .lineSpacing(4)
        }
        .padding(17)
        .paperCard(fill: theme.primarySoft, radius: 8)
        .accessibilityIdentifier("meow-import.safety")

        if let message = controller.failureMessage {
            Label(message, systemImage: "xmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.error)
                .accessibilityIdentifier("meow-import.failure")
        }
    }

    private func success(_ result: LedgerMeowImportResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(theme.primary)
            Text("导入完成").font(.title2.bold())
            Text("已导入 \(result.importedRecordCount) 笔，跳过 \(result.skippedDuplicateRecordCount) 笔已存在记录。")
                .font(.body)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("新增账本 / 分类")
                    Spacer()
                    Text("\(result.createdBookCount) / \(result.createdCategoryCount)").fontWeight(.semibold)
                }
                HStack {
                    Text("支出 \(result.importedExpenseCount) 笔")
                    Spacer()
                    Text(result.importedExpenseTotalText).fontWeight(.semibold)
                }
                HStack {
                    Text("收入 \(result.importedIncomeCount) 笔")
                    Spacer()
                    Text(result.importedIncomeTotalText).fontWeight(.semibold)
                }
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard()
            VStack(alignment: .leading, spacing: 6) {
                Text("导入前备份").font(.caption).foregroundStyle(theme.muted)
                Text(result.backupName).font(.system(.body, design: .monospaced))
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meow-import.success")
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("无法生成预览", systemImage: "doc.badge.ellipsis")
                .font(.title3.bold())
            Text(controller.failureMessage ?? "请重新选择喵喵记账导出的 CSV 文件。")
                .foregroundStyle(theme.muted)
            Button("重新选择") { controller.requestFileSelection() }
                .buttonStyle(PaperButtonStyle(fill: theme.primarySoft))
                .accessibilityIdentifier("meow-import.reselect")
        }
        .padding(18)
        .paperCard()
    }

    @ViewBuilder
    private var actionBar: some View {
        if let selection = controller.selection, controller.result == nil {
            HStack(spacing: 12) {
                Button("重新选择") { controller.requestFileSelection() }
                    .buttonStyle(PaperButtonStyle())
                    .disabled(controller.isImporting)
                    .accessibilityIdentifier("meow-import.reselect")
                Button {
                    Task { await controller.importSelection() }
                } label: {
                    if controller.isImporting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(selection.issues.isEmpty ? "创建备份并导入" : "修复错误后导入")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(PaperButtonStyle(fill: theme.primarySoft))
                .disabled(!selection.canImport || controller.isImporting)
                .accessibilityIdentifier("meow-import.confirm")
            }
            .padding(14)
            .background(theme.surface.shadow(color: theme.shadow.opacity(0.35), radius: 8, y: -2))
        } else if controller.result != nil {
            Button("完成") { controller.cancelReview() }
                .buttonStyle(PaperButtonStyle(fill: theme.primarySoft))
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(theme.surface)
                .accessibilityIdentifier("meow-import.done")
        }
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(theme.primary)
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
    }

    private func summaryLine(title: String, count: Int, minorUnits: Int64?) -> some View {
        HStack {
            Text("\(title) \(count) 笔")
            Spacer()
            Text(minorUnits.map { "¥" + LedgerAmount.format(minorUnits: $0) } ?? "金额合计超出范围")
                .fontWeight(.semibold)
        }
    }

    private func dateRange(_ preview: LedgerMeowCombinedPreview) -> String {
        guard let earliest = preview.earliestDate, let latest = preview.latestDate else { return "—" }
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return "\(earliest.formatted(style)) – \(latest.formatted(style))"
    }
}
