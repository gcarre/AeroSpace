@testable import AppBundle
import XCTest

@MainActor
final class DwindleLayoutTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.defaultRootContainerLayout = .dwindle
    }

    func testNewWindowsRecursivelySplitMostRecentWindow() {
        let workspace = Workspace.get(byName: name)
        let window1 = newDwindleWindow(id: 1, in: workspace)
        _ = newDwindleWindow(id: 2, in: workspace)
        _ = newDwindleWindow(id: 3, in: workspace)
        _ = newDwindleWindow(id: 4, in: workspace)

        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .dwindle([
                .window(1),
                .v_tiles([
                    .window(2),
                    .h_tiles([.window(3), .window(4)]),
                ]),
            ]),
        )
        assertEquals(workspace.rootTilingContainer.layout, .dwindle)
        assertEquals(window1.nodeWorkspace, workspace)
    }

    func testSplitOrientationUsesTargetGeometry() {
        let workspace = Workspace.get(byName: name)
        let window1 = newDwindleWindow(id: 1, in: workspace)
        window1.lastAppliedLayoutVirtualRect = Rect(topLeftX: 0, topLeftY: 0, width: 400, height: 800)
        _ = newDwindleWindow(id: 2, in: workspace)

        assertEquals(workspace.rootTilingContainer.orientation, .v)
        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .dwindle([.window(1), .window(2)]),
        )
    }

    func testLayoutCommandRebuildsExistingTreeAsDwindle() async {
        config.defaultRootContainerLayout = .tiles
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("layout --root dwindle").cmdOrDie
            .run(.defaultEnv.withWorkspaceName(name), .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .dwindle([
                .window(1),
                .v_tiles([.window(2), .window(3)]),
            ]),
        )
    }

    func testNormalizationKeepsDwindleOnRoot() {
        config.enableNormalizationFlattenContainers = true
        let workspace = Workspace.get(byName: name)
        let window1 = newDwindleWindow(id: 1, in: workspace)
        _ = newDwindleWindow(id: 2, in: workspace)
        _ = newDwindleWindow(id: 3, in: workspace)

        window1.unbindFromParent()
        workspace.normalizeContainers()

        assertEquals(workspace.rootTilingContainer.layout, .dwindle)
        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .dwindle([.window(2), .window(3)]),
        )
    }

    func testSwitchingBackToTilesFlattensDwindleTree() async {
        let workspace = Workspace.get(byName: name)
        _ = newDwindleWindow(id: 1, in: workspace)
        _ = newDwindleWindow(id: 2, in: workspace)
        _ = newDwindleWindow(id: 3, in: workspace)

        let result = await parseCommand("layout --root tiles").cmdOrDie
            .run(.defaultEnv.withWorkspaceName(name), .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .h_tiles([.window(1), .window(2), .window(3)]),
        )
    }

    func testMoveToWorkspaceUsesDwindleInsertion() {
        let targetWorkspace = Workspace.get(byName: "target")
        _ = newDwindleWindow(id: 1, in: targetWorkspace)
        _ = newDwindleWindow(id: 2, in: targetWorkspace)

        let sourceWorkspace = Workspace.get(byName: "source")
        let movedWindow = TestWindow.new(id: 3, parent: sourceWorkspace.rootTilingContainer)
        let result = moveWindowToWorkspace(
            movedWindow,
            targetWorkspace,
            CmdIoImpl.emptyStdinIgnoringOut,
            focusFollowsWindow: false,
            failIfNoop: false,
        )

        assertEquals(result.rawValue, 0)
        assertTrue(sourceWorkspace.isEffectivelyEmpty)
        assertEquals(
            targetWorkspace.rootTilingContainer.layoutDescription,
            .dwindle([
                .window(1),
                .v_tiles([.window(2), .window(3)]),
            ]),
        )
    }

    func testMouseMoveToWorkspaceSplitsWindowUnderPointer() {
        let targetWorkspace = Workspace.get(byName: "target")
        _ = newDwindleWindow(id: 1, in: targetWorkspace)
        let targetWindow = newDwindleWindow(id: 2, in: targetWorkspace)
        targetWindow.lastAppliedLayoutVirtualRect = Rect(topLeftX: 1000, topLeftY: 0, width: 1000, height: 500)
        targetWindow.lastAppliedLayoutPhysicalRect = targetWindow.lastAppliedLayoutVirtualRect

        let sourceWorkspace = Workspace.get(byName: "source")
        let movedWindow = TestWindow.new(id: 3, parent: sourceWorkspace.rootTilingContainer)
        moveTilingWindowToWorkspace(
            movedWindow,
            targetWorkspace,
            CGPoint(x: 1100, y: 250),
            targetWindow,
        )

        assertTrue(sourceWorkspace.isEffectivelyEmpty)
        assertEquals(
            targetWorkspace.rootTilingContainer.layoutDescription,
            .dwindle([
                .window(1),
                .h_tiles([.window(3), .window(2)]),
            ]),
        )
    }

    func testMouseMoveToWorkspaceUsesClosestWindowWhenDroppedInGap() {
        let targetWorkspace = Workspace.get(byName: "target")
        let window1 = newDwindleWindow(id: 1, in: targetWorkspace)
        let window2 = newDwindleWindow(id: 2, in: targetWorkspace)
        window1.lastAppliedLayoutVirtualRect = Rect(topLeftX: 0, topLeftY: 0, width: 490, height: 1000)
        window1.lastAppliedLayoutPhysicalRect = window1.lastAppliedLayoutVirtualRect
        window2.lastAppliedLayoutVirtualRect = Rect(topLeftX: 510, topLeftY: 0, width: 490, height: 1000)
        window2.lastAppliedLayoutPhysicalRect = window2.lastAppliedLayoutVirtualRect

        let sourceWorkspace = Workspace.get(byName: "source")
        let movedWindow = TestWindow.new(id: 3, parent: sourceWorkspace.rootTilingContainer)
        moveTilingWindowToWorkspace(movedWindow, targetWorkspace, CGPoint(x: 505, y: 750))

        assertEquals(
            targetWorkspace.rootTilingContainer.layoutDescription,
            .dwindle([
                .window(1),
                .v_tiles([.window(2), .window(3)]),
            ]),
        )
    }

    func testToggleSplitChangesOnlyFocusedWindowsImmediateParent() async {
        config.enableNormalizationOppositeOrientationForNestedContainers = true
        let workspace = Workspace.get(byName: name)
        _ = newDwindleWindow(id: 1, in: workspace)
        _ = newDwindleWindow(id: 2, in: workspace)
        let window3 = newDwindleWindow(id: 3, in: workspace)
        _ = newDwindleWindow(id: 4, in: workspace)
        assertTrue(window3.focusWindow())

        let result = await parseCommand("layout toggle-split").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .dwindle([
                .window(1),
                .v_tiles([
                    .window(2),
                    .v_tiles([.window(3), .window(4)]),
                ]),
            ]),
        )
    }

    func testToggleSplitChangesRootSplit() async {
        let workspace = Workspace.get(byName: name)
        let window1 = newDwindleWindow(id: 1, in: workspace)
        _ = newDwindleWindow(id: 2, in: workspace)
        assertTrue(window1.focusWindow())

        let result = await parseCommand("layout toggle-split").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(workspace.rootTilingContainer.orientation, .v)
        assertEquals(workspace.rootTilingContainer.layout, .dwindle)
    }

    func testToggleSplitFailsWithoutSplit() async {
        let workspace = Workspace.get(byName: name)
        let window = newDwindleWindow(id: 1, in: workspace)
        assertTrue(window.focusWindow())

        let result = await parseCommand("layout toggle-split").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["The focused window has no dwindle split to toggle"])
    }

    func testToggleSplitFailsOutsideDwindle() async {
        config.defaultRootContainerLayout = .tiles
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertTrue(window.focusWindow())

        let result = await parseCommand("layout toggle-split").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["toggle-split is only available in dwindle layout"])
    }

    private func newDwindleWindow(id: UInt32, in workspace: Workspace) -> TestWindow {
        let data = unbindAndGetBindingDataForNewTilingWindow(workspace, window: nil)
        return TestWindow.new(id: id, parent: data.parent, adaptiveWeight: data.adaptiveWeight)
    }
}
