import SwiftUI
import YoloLedgerCore

private enum LedgerDestination: String, CaseIterable, Identifiable {
    case bills, details, books, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .bills: "账单"
        case .details: "明细"
        case .books: "账本"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .bills: "doc.text"
        case .details: "list.bullet.rectangle"
        case .books: "books.vertical"
        case .settings: "gearshape"
        }
    }
}

/// M1 navigation shell. The app entry supplies the concrete book repository.
@MainActor
public struct YoloLedgerRootView: View {
    @State private var booksModel: BookListModel
    @State private var mobileSelection: LedgerDestination = .bills
    @State private var desktopSelection: LedgerDestination? = .bills

    public init(repository: any LedgerBookRepository) {
        _booksModel = State(initialValue: BookListModel(repository: repository))
    }

    public var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(LedgerDestination.allCases, selection: $desktopSelection) { destination in
                NavigationLink(value: destination) {
                    Label(destination.title, systemImage: destination.symbol)
                }
                .accessibilityIdentifier("navigation.\(destination.rawValue)")
            }
            .listStyle(.sidebar)
            .navigationTitle("有落")
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            destinationView(desktopSelection ?? .bills)
                .navigationTitle((desktopSelection ?? .bills).title)
        }
        .tint(.orange)
        #else
        TabView(selection: $mobileSelection) {
            ForEach(LedgerDestination.allCases) { destination in
                NavigationStack {
                    destinationView(destination)
                        .navigationTitle(destination.title)
                }
                .tabItem { Label(destination.title, systemImage: destination.symbol) }
                .tag(destination)
            }
        }
        .tint(.orange)
        #endif
    }

    @ViewBuilder
    private func destinationView(_ destination: LedgerDestination) -> some View {
        switch destination {
        case .bills:
            ContentUnavailableView(
                "暂无账单",
                systemImage: destination.symbol,
                description: Text("收支记录功能准备中。")
            )
        case .details:
            ContentUnavailableView(
                "暂无明细",
                systemImage: destination.symbol,
                description: Text("记账明细与筛选功能准备中。")
            )
        case .books:
            BookListView(model: booksModel)
        case .settings:
            SettingsPlaceholderView()
        }
    }
}

@MainActor
private struct BookListView: View {
    let model: BookListModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView("正在读取账本")
            case .loaded(let books) where books.isEmpty:
                ContentUnavailableView(
                    "暂无账本",
                    systemImage: "books.vertical",
                    description: Text("账本管理功能准备中。")
                )
            case .loaded(let books):
                List(books) { book in
                    Label(book.name, systemImage: "book.closed")
                }
            case .failed:
                ContentUnavailableView {
                    Label("账本读取失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("请稍后重试。")
                } actions: {
                    Button("重试") {
                        Task { await model.load() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("books.retry")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await model.load() }
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        Form {
            Section("关于有落") {
                LabeledContent("名称", value: "有落 · YoloLedger")
                Text("当前版本用于预览页面导航，记账功能准备中。")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.placeholder")
            }
        }
        .formStyle(.grouped)
    }
}
