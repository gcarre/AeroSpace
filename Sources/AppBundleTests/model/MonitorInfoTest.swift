@testable import AppBundle
import XCTest

@MainActor
final class MonitorInfoTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testActiveWorkspaceFallsBackForStaleMonitorSnapshot() {
        let visibleWorkspace = focus.workspace
        let staleMonitor = TestMonitorInfo(
            rect: Rect(topLeftX: 10_000, topLeftY: 0, width: 1920, height: 1080),
        )

        assertEquals(staleMonitor.activeWorkspace, visibleWorkspace)
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
