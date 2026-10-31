import SwiftUI

enum HorizontalPagingDirection: String, Equatable, Sendable {
    case previous
    case next

    var offsetSign: CGFloat { self == .previous ? 1 : -1 }
}

enum HorizontalPagingSource: String, Equatable, Sendable {
    case gesture
    case button
}

enum HorizontalPagingGesturePriority: Sendable {
    case simultaneous
    case high
}

enum HorizontalPagingPhysics {
    static let horizontalDominanceRatio: CGFloat = 1.2
    static let completionDistance: CGFloat = 48
    static let minimumFlickDistance: CGFloat = 32
    static let predictedCompletionDistance: CGFloat = 120

    static func interactiveOffset(
        horizontal: CGFloat,
        vertical: CGFloat,
        pageWidth: CGFloat
    ) -> CGFloat {
        guard pageWidth > 0,
              abs(horizontal) > abs(vertical) * horizontalDominanceRatio
        else { return 0 }
        return min(max(horizontal, -pageWidth), pageWidth)
    }

    static func completionDirection(
        horizontal: CGFloat,
        vertical: CGFloat,
        predictedHorizontal: CGFloat,
        predictedVertical: CGFloat
    ) -> HorizontalPagingDirection? {
        guard abs(horizontal) > abs(vertical) * horizontalDominanceRatio else { return nil }
        if abs(horizontal) >= completionDistance {
            return horizontal < 0 ? .next : .previous
        }
        guard abs(horizontal) >= minimumFlickDistance,
              abs(predictedHorizontal) >= predictedCompletionDistance,
              abs(predictedHorizontal) > abs(predictedVertical) * horizontalDominanceRatio
        else { return nil }
        return predictedHorizontal < 0 ? .next : .previous
    }
}

struct HorizontalPagingProxy {
    let moveToPrevious: () -> Void
    let moveToNext: () -> Void
}

@MainActor
struct HorizontalPagingView<Page: Hashable, Content: View>: View {
    let page: Page
    let previousPage: (Page) -> Page
    let nextPage: (Page) -> Page
    let selectPage: (Page) -> Void
    let gesturePriority: HorizontalPagingGesturePriority
    let debugIdentifier: String?
    @ViewBuilder let content: (Page, HorizontalPagingProxy) -> Content

    @State private var pageWidth: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isTransitioning = false
    @State private var transitionTask: Task<Void, Never>?
    @State private var debugPhase = "idle"
    @State private var lastDirection: HorizontalPagingDirection?
    @State private var lastSource: HorizontalPagingSource?
    @State private var completedTransitionCount = 0

    private let completionDuration = 0.28
    private let reboundDuration = 0.24

    init(
        page: Page,
        previousPage: @escaping (Page) -> Page,
        nextPage: @escaping (Page) -> Page,
        selectPage: @escaping (Page) -> Void,
        gesturePriority: HorizontalPagingGesturePriority = .simultaneous,
        debugIdentifier: String? = nil,
        @ViewBuilder content: @escaping (Page, HorizontalPagingProxy) -> Content
    ) {
        self.page = page
        self.previousPage = previousPage
        self.nextPage = nextPage
        self.selectPage = selectPage
        self.gesturePriority = gesturePriority
        self.debugIdentifier = debugIdentifier
        self.content = content
    }

    var body: some View {
        let proxy = HorizontalPagingProxy(
            moveToPrevious: { beginMove(.previous, source: .button) },
            moveToNext: { beginMove(.next, source: .button) }
        )

        HorizontalPagesLayout(offset: dragOffset) {
            content(previousPage(page), proxy)
                .id(previousPage(page))
                .environment(\.horizontalPagingPageIsActive, false)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityHidden(true)
            content(page, proxy)
                .id(page)
                .environment(\.horizontalPagingPageIsActive, true)
                .allowsHitTesting(!isDragging && !isTransitioning)
            content(nextPage(page), proxy)
                .id(nextPage(page))
                .environment(\.horizontalPagingPageIsActive, false)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityHidden(true)
        }
        .clipped()
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: HorizontalPagingWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(HorizontalPagingWidthKey.self) { newWidth in
            guard newWidth > 0, abs(newWidth - pageWidth) > 0.5 else { return }
            if isTransitioning { cancelTransition() }
            pageWidth = newWidth
        }
        .modifier(HorizontalPagingGestureModifier(gesture: pagingGesture, priority: gesturePriority))
        .overlay(alignment: .topLeading) { debugMarker }
        .onChange(of: page) { _, _ in
            guard !isTransitioning, dragOffset != 0 else { return }
            resetOffsetWithoutAnimation()
        }
        .onDisappear {
            transitionTask?.cancel()
            transitionTask = nil
        }
    }

    private var pagingGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isTransitioning else { return }
                let offset = HorizontalPagingPhysics.interactiveOffset(
                    horizontal: value.translation.width,
                    vertical: value.translation.height,
                    pageWidth: pageWidth
                )
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragOffset = offset
                    if offset != 0 {
                        isDragging = true
                        debugPhase = "dragging"
                        lastDirection = offset < 0 ? .next : .previous
                        lastSource = .gesture
                    }
                }
            }
            .onEnded { value in
                guard !isTransitioning else { return }
                let direction = HorizontalPagingPhysics.completionDirection(
                    horizontal: value.translation.width,
                    vertical: value.translation.height,
                    predictedHorizontal: value.predictedEndTranslation.width,
                    predictedVertical: value.predictedEndTranslation.height
                )
                if let direction {
                    beginMove(direction, source: .gesture)
                } else if isDragging {
                    rebound()
                }
            }
    }

    private func beginMove(_ direction: HorizontalPagingDirection, source: HorizontalPagingSource) {
        guard !isTransitioning, pageWidth > 0 else { return }
        transitionTask?.cancel()
        isTransitioning = true
        debugPhase = "animating"
        lastDirection = direction
        lastSource = source
        let targetPage = direction == .previous ? previousPage(page) : nextPage(page)

        withAnimation(.snappy(duration: completionDuration, extraBounce: 0)) {
            dragOffset = direction.offsetSign * pageWidth
        }
        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(completionDuration))
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectPage(targetPage)
                dragOffset = 0
                isDragging = false
                isTransitioning = false
                debugPhase = "idle"
                completedTransitionCount += 1
            }
            transitionTask = nil
        }
    }

    private func rebound() {
        guard !isTransitioning else { return }
        transitionTask?.cancel()
        isTransitioning = true
        debugPhase = "rebounding"
        lastDirection = nil
        lastSource = .gesture
        withAnimation(.spring(response: reboundDuration, dampingFraction: 0.84)) {
            dragOffset = 0
        }
        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(reboundDuration))
            guard !Task.isCancelled else { return }
            isTransitioning = false
            isDragging = false
            debugPhase = "idle"
            transitionTask = nil
        }
    }

    private func cancelTransition() {
        transitionTask?.cancel()
        transitionTask = nil
        resetOffsetWithoutAnimation()
        isDragging = false
        isTransitioning = false
        debugPhase = "idle"
    }

    private func resetOffsetWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { dragOffset = 0 }
    }

    @ViewBuilder
    private var debugMarker: some View {
        #if DEBUG
        if let debugIdentifier {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("横向分页状态")
                .accessibilityIdentifier(debugIdentifier)
                .accessibilityValue(debugValue)
        }
        #endif
    }

    private var debugValue: String {
        let direction = lastDirection?.rawValue ?? "bounce"
        let source = lastSource?.rawValue ?? "none"
        return "\(debugPhase),\(direction),\(source),\(completedTransitionCount)"
    }
}

private struct HorizontalPagesLayout: Layout {
    var offset: CGFloat

    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let fallbackWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? fallbackWidth
        let pageProposal = ProposedViewSize(width: width, height: nil)
        let height = subviews.map { $0.sizeThatFits(pageProposal).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let pageProposal = ProposedViewSize(width: bounds.width, height: nil)
        for (index, subview) in subviews.enumerated() {
            let relativePage = CGFloat(index - 1)
            subview.place(
                at: CGPoint(
                    x: bounds.minX + relativePage * bounds.width + offset,
                    y: bounds.minY
                ),
                anchor: .topLeading,
                proposal: pageProposal
            )
        }
    }
}

private struct HorizontalPagingWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HorizontalPagingGestureModifier<PagingGesture: Gesture>: ViewModifier {
    let gesture: PagingGesture
    let priority: HorizontalPagingGesturePriority

    @ViewBuilder
    func body(content: Content) -> some View {
        switch priority {
        case .simultaneous:
            content.simultaneousGesture(gesture)
        case .high:
            content.highPriorityGesture(gesture)
        }
    }
}

private struct HorizontalPagingPageIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var horizontalPagingPageIsActive: Bool {
        get { self[HorizontalPagingPageIsActiveKey.self] }
        set { self[HorizontalPagingPageIsActiveKey.self] = newValue }
    }
}

private struct PagingAccessibilityIdentifier: ViewModifier {
    @Environment(\.horizontalPagingPageIsActive) private var isActive
    let identifier: String

    func body(content: Content) -> some View {
        content
            .accessibilityIdentifier(isActive ? identifier : "\(identifier).adjacent")
            .accessibilityHidden(!isActive)
    }
}

extension View {
    func pagingAccessibilityIdentifier(_ identifier: String) -> some View {
        modifier(PagingAccessibilityIdentifier(identifier: identifier))
    }
}
