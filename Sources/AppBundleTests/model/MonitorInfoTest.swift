@testable import AppBundle
import AppKit
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct MonitorInfoTest {
    init() { setUpWorkspacesForTests() }

    @Test func testVisibleWorkspaceFallsBackForStaleMonitorSnapshot() {
        let visibleWorkspace = globalFocus.workspace
        let staleMonitor = TestMonitorInfo(
            rect: Rect(topLeftX: 10000, topLeftY: 0, width: 1920, height: 1080),
        )

        assertEquals(staleMonitor.visibleWorkspace, visibleWorkspace)
    }

    @Test func testGeometryRefreshesWhenDisplaySizeChangesAtSameOrigin() {
        let workspace = globalFocus.workspace
        let monitor = workspace.nodeMonitorInfo.orDie().toMonitorOrRearrangeMonitors()
        let resizedMonitor = TestMonitorInfo(
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1728, height: 1117),
        )
        defer { gcMonitors() }

        gcMonitors([resizedMonitor])

        assertTrue(workspace.nodeMonitorInfo.orDie().toMonitorOrRearrangeMonitors() === monitor)
        assertEquals(workspace.workspaceMonitorInfo.rect.width, 1728)
        assertEquals(workspace.rootTilingContainer.hWeight, 1728)
    }
}

private struct TestMonitorInfo: MonitorInfo {
    let monitorAppKitNsScreenScreensId = 2
    let name = "Stale Test Monitor"
    let rect: Rect
    var visibleRect: Rect { rect }
    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
    let isMain = false
}
