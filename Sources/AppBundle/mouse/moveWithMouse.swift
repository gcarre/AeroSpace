import AppKit
import Common

@MainActor
private var moveWithMouseTask: Task<(), any Error>? = nil

func movedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let nativeWindowId = ax.containingNativeWindowId()
    let notif = notif as String
    let pid = ax.pid
    Task.startUnstructured { @MainActor in
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        guard let nativeWindowId,
              let pid,
              let window = Window.get(byNativeId: nativeWindowId, pid: pid),
              try await isManipulatedWithMouse(window)
        else {
            scheduleCancellableCompleteRefreshSession(.ax(notif))
            return
        }
        moveWithMouseTask?.cancel()
        moveWithMouseTask = Task.startUnstructured {
            try checkCancellation()
            try await runLightSession(.ax(notif), token) {
                try await moveWithMouse(window)
            }
        }
    }
}

@MainActor
private func moveWithMouse(_ window: Window) async throws { // todo cover with tests
    resetClosedWindowsCache()
    switch window.windowParentCases {
        case .floatingWindowsContainer:
            try await moveFloatingWindow(window)
        case .macosFullscreenWindowsContainer, .macosMinimizedWindowsContainer, .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return // Unconventional windows can't be moved with mouse
        case .tilingContainer:
            moveTilingWindow(window)
        case nil: return
    }
}

@MainActor
private func moveFloatingWindow(_ window: Window) async throws {
    guard let targetWorkspace = try await window.getCenter(.cancellable)?.monitorApproximation.visibleWorkspace else { return }
    guard let parent = window.parent else { return }
    if targetWorkspace != parent {
        window.bindAsFloatingWindow(to: targetWorkspace)
    }
}

@MainActor
private func moveTilingWindow(_ window: Window) {
    currentlyManipulatedWithMouseWindowId = window.windowId
    window.lastAppliedLayoutPhysicalRect = nil
    let mouseLocation = mouseLocation
    let targetWorkspace = mouseLocation.monitorApproximation.visibleWorkspace
    let swapTarget = mouseLocation
        .findWindowRecursively(in: targetWorkspace.rootTilingContainer, virtual: false, fullscreenCoversAll: false)?
        .takeIf { $0 != window }
    if targetWorkspace != window.nodeWorkspace { // Move window to a different monitor
        moveTilingWindowToWorkspace(window, targetWorkspace, mouseLocation, swapTarget)
    } else if let swapTarget {
        swapWindows(mruDominant: window, swapTarget)
    }
}

@MainActor
func moveTilingWindowToWorkspace(
    _ window: Window,
    _ targetWorkspace: Workspace,
    _ dropPoint: Point,
    _ windowUnderPointer: Window? = nil,
) {
    if targetWorkspace.rootTilingContainer.layout == .dwindle {
        let dropTarget = windowUnderPointer ?? targetWorkspace.rootTilingContainer.allInhabitedLeafWindowsRecursive
            .filter { $0 != window }
            .compactMap { candidate -> (window: Window, distance: CGFloat)? in
                guard let rect = candidate.lastAppliedLayoutPhysicalRect else { return nil }
                return (candidate, dropPoint.distance(toOuterFrame: rect))
            }
            .minBy { $0.distance }?
            .window
        let data = unbindAndGetBindingDataForDwindleDrop(
            targetWorkspace,
            window: window,
            targetWindow: dropTarget,
            dropPoint: dropPoint,
        )
        window.bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
    } else {
        let swapTarget = windowUnderPointer
        let parent: TilingContainer
        let index: Int
        if let swapTarget,
           let (targetParent, targetIndex) = swapTarget.nearestAliveTilingParent(),
           let targetRect = swapTarget.lastAppliedLayoutPhysicalRect
        {
            parent = targetParent
            index = dropPoint.getProjection(parent.orientation) >= targetRect.center.getProjection(parent.orientation)
                ? targetIndex + 1
                : targetIndex
        } else {
            parent = targetWorkspace.rootTilingContainer
            index = 0
        }
        window.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: index)
    }
}

@MainActor
func swapWindows(mruDominant window1: Window, _ window2: Window) {
    if window1 == window2 { return }

    let binding2 = window2.unbindFromParent()
    let binding1 = window1.unbindFromParent()

    window2.bind(to: binding1.parent, adaptiveWeight: binding1.adaptiveWeight, index: binding1.index)
    window1.bind(to: binding2.parent, adaptiveWeight: binding2.adaptiveWeight, index: binding2.index)
}

extension Point {
    @MainActor
    func findWindowRecursively(
        in tree: TilingContainer,
        virtual: Bool,
        fullscreenCoversAll: Bool,
    ) -> Window? {
        if fullscreenCoversAll {
            if let window = tree.mostRecentWindowRecursive, window.isFullscreen {
                return window
            }
        }
        return _findWindowRecursively(in: tree, virtual: virtual)
    }

    @MainActor
    private func _findWindowRecursively(in tree: TilingContainer, virtual: Bool) -> Window? {
        let point = self
        let target: TreeNode? = switch tree.layout {
            case .dwindle, .tiles:
                tree.inhabitedChildren.first(where: {
                    (virtual ? $0.lastAppliedLayoutVirtualRect : $0.lastAppliedLayoutPhysicalRect)?.contains(point) == true
                })
            case .accordion:
                tree.mostRecentInhabitedChild
        }
        guard let target else { return nil }
        return switch target.tilingTreeNodeCasesOrDie() {
            case .window(let window): window
            case .tilingContainer(let container): _findWindowRecursively(in: container, virtual: virtual)
        }
    }
}
