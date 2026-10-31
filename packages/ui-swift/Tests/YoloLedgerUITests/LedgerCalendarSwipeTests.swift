import Testing
@testable import YoloLedgerUI

@MainActor
struct HorizontalPagingPhysicsTests {
    @Test
    func leftSwipeMovesToNextMonth() {
        #expect(HorizontalPagingPhysics.completionDirection(
            horizontal: -96,
            vertical: 12,
            predictedHorizontal: -110,
            predictedVertical: 14
        ) == .next)
    }

    @Test
    func rightSwipeMovesToPreviousMonth() {
        #expect(HorizontalPagingPhysics.completionDirection(
            horizontal: 96,
            vertical: -12,
            predictedHorizontal: 110,
            predictedVertical: -14
        ) == .previous)
    }

    @Test
    func shortOrVerticallyDominantDragDoesNotMoveMonth() {
        #expect(HorizontalPagingPhysics.completionDirection(
            horizontal: 31,
            vertical: 0,
            predictedHorizontal: 200,
            predictedVertical: 0
        ) == nil)
        #expect(HorizontalPagingPhysics.completionDirection(
            horizontal: 47,
            vertical: 2,
            predictedHorizontal: 80,
            predictedVertical: 3
        ) == nil)
        #expect(HorizontalPagingPhysics.completionDirection(
            horizontal: 72,
            vertical: 64,
            predictedHorizontal: 180,
            predictedVertical: 120
        ) == nil)
    }

    @Test
    func predictedFlickCanCompleteAfterMinimumTravel() {
        #expect(HorizontalPagingPhysics.completionDirection(
            horizontal: -36,
            vertical: 4,
            predictedHorizontal: -160,
            predictedVertical: 12
        ) == .next)
    }

    @Test
    func interactiveOffsetFollowsOnlyHorizontalDragAndClampsToPage() {
        #expect(HorizontalPagingPhysics.interactiveOffset(horizontal: 80, vertical: 10, pageWidth: 300) == 80)
        #expect(HorizontalPagingPhysics.interactiveOffset(horizontal: -400, vertical: 10, pageWidth: 300) == -300)
        #expect(HorizontalPagingPhysics.interactiveOffset(horizontal: 60, vertical: 55, pageWidth: 300) == 0)
    }
}
