import XCTest
@testable import DockPlus

final class DockGeometryTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1055)

    func testSnapToAllFourEdgesAndOrientationFlip() {
        // Bottom edge (within 16 pt)
        let bottomFrame = CGRect(x: 800, y: 10, width: 300, height: 76)
        let bottomPlacement = DockGeometry.placementForDraggedFrame(bottomFrame, in: visibleFrame, displayUUID: "D1")
        XCTAssertEqual(bottomPlacement.snappedEdge, .bottom)
        XCTAssertEqual(bottomPlacement.snappedEdge?.preferredOrientation, .horizontal)

        // Top edge (within 16 pt)
        let topFrame = CGRect(x: 800, y: visibleFrame.maxY - 76 - 8, width: 300, height: 76)
        let topPlacement = DockGeometry.placementForDraggedFrame(topFrame, in: visibleFrame, displayUUID: "D1")
        XCTAssertEqual(topPlacement.snappedEdge, .top)
        XCTAssertEqual(topPlacement.snappedEdge?.preferredOrientation, .horizontal)

        // Left edge (within 16 pt)
        let leftFrame = CGRect(x: 5, y: 400, width: 76, height: 300)
        let leftPlacement = DockGeometry.placementForDraggedFrame(leftFrame, in: visibleFrame, displayUUID: "D1")
        XCTAssertEqual(leftPlacement.snappedEdge, .left)
        XCTAssertEqual(leftPlacement.snappedEdge?.preferredOrientation, .vertical)

        // Right edge (within 16 pt)
        let rightFrame = CGRect(x: visibleFrame.maxX - 76 - 12, y: 400, width: 76, height: 300)
        let rightPlacement = DockGeometry.placementForDraggedFrame(rightFrame, in: visibleFrame, displayUUID: "D1")
        XCTAssertEqual(rightPlacement.snappedEdge, .right)
        XCTAssertEqual(rightPlacement.snappedEdge?.preferredOrientation, .vertical)
    }

    func testAwayFromEdgesRemainsFloating() {
        let centerFrame = CGRect(x: 600, y: 500, width: 300, height: 76)
        let placement = DockGeometry.placementForDraggedFrame(centerFrame, in: visibleFrame, displayUUID: "D1")
        guard case .floating(let x, let y, let uuid) = placement else {
            XCTFail("Expected floating placement, got \(placement)")
            return
        }
        XCTAssertEqual(x, 600, accuracy: 0.1)
        XCTAssertEqual(y, 500, accuracy: 0.1)
        XCTAssertEqual(uuid, "D1")
    }

    func testClampsOffScreenFloatingDockIntoVisibleFrame() {
        let offScreenPlacement = DockConfig.Placement.floating(x: -150, y: 1200, displayUUID: nil)
        let panelSize = CGSize(width: 300, height: 76)

        let clamped = DockGeometry.visibleFrame(for: offScreenPlacement, panelSize: panelSize, in: visibleFrame)
        XCTAssertTrue(visibleFrame.contains(clamped))
        XCTAssertEqual(clamped.minX, visibleFrame.minX, accuracy: 0.1)
        XCTAssertEqual(clamped.maxY, visibleFrame.maxY, accuracy: 0.1)
    }

    func testAutoHideSliverFramesOnAllFourEdges() {
        let horizDock = CGRect(x: 800, y: 6, width: 300, height: 76)
        let bottomHidden = DockGeometry.autoHiddenFrame(for: .bottom, visibleDockFrame: horizDock, screenFrame: screenFrame)
        XCTAssertLessThan(bottomHidden.maxY, screenFrame.minY)

        let topHidden = DockGeometry.autoHiddenFrame(for: .top, visibleDockFrame: horizDock, screenFrame: screenFrame)
        XCTAssertGreaterThan(topHidden.minY, screenFrame.maxY)

        let vertDock = CGRect(x: 6, y: 400, width: 76, height: 300)
        let leftHidden = DockGeometry.autoHiddenFrame(for: .left, visibleDockFrame: vertDock, screenFrame: screenFrame)
        XCTAssertLessThan(leftHidden.maxX, screenFrame.minX)

        let rightHidden = DockGeometry.autoHiddenFrame(for: .right, visibleDockFrame: vertDock, screenFrame: screenFrame)
        XCTAssertGreaterThan(rightHidden.minX, screenFrame.maxX)
    }

    func testClippedWindowLayoutNeverBleedsOntoAdjacentMonitor() {
        // Two side-by-side monitors: Left [0..1920], Right [1920..3840]
        let leftDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rightEdgePill = CGRect(x: 1920 - 8 - 76, y: 400, width: 76, height: 300)
        let desiredInsets = DockEdgeInsets(top: 40, bottom: 40, left: 60, right: 12)

        let layout = DockGeometry.clippedWindowLayout(
            forPillFrame: rightEdgePill,
            desiredInsets: desiredInsets,
            within: leftDisplay
        )

        // Window frame must stay strictly inside leftDisplay so nothing bleeds onto right monitor
        XCTAssertTrue(leftDisplay.contains(layout.windowFrame))
        XCTAssertLessThanOrEqual(layout.windowFrame.maxX, leftDisplay.maxX)
        // Right inset shrinks from 12 to 8 (matching edgeInset), inward left inset stays full 60
        XCTAssertEqual(layout.insets.right, 8, accuracy: 0.1)
        XCTAssertEqual(layout.insets.left, 60, accuracy: 0.1)

        // Retreated stage offset pushes pill strictly past the right window edge
        let pillInWindow = CGRect(
            x: layout.insets.left,
            y: layout.insets.bottom,
            width: rightEdgePill.width,
            height: rightEdgePill.height
        )
        let offset = DockGeometry.retreatedStageOffset(
            for: .right,
            pillFrameInWindow: pillInWindow,
            windowSize: layout.windowFrame.size
        )
        XCTAssertGreaterThan(pillInWindow.minX + offset.x, layout.windowFrame.width)
        XCTAssertEqual(offset.y, 0, accuracy: 0.1)
    }
}
