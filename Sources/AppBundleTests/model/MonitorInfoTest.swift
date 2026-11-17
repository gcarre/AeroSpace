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
