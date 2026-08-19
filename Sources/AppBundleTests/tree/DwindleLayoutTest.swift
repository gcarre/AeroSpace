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

        let result = await parseCommand("layout --root dwindle").cmdOrDie.run(.defaultEnv, .emptyStdin)

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

        let result = await parseCommand("layout --root tiles").cmdOrDie.run(.defaultEnv, .emptyStdin)

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

    private func newDwindleWindow(id: UInt32, in workspace: Workspace) -> TestWindow {
        let data = unbindAndGetBindingDataForNewTilingWindow(workspace, window: nil)
        return TestWindow.new(id: id, parent: data.parent, adaptiveWeight: data.adaptiveWeight)
    }
}
