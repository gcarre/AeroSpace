import AppKit
import Common

// Leaves `window` unbound so the caller can insert it at the returned split.
@MainActor
func unbindAndGetBindingDataForNewTilingWindow(
    _ workspace: Workspace,
    window: Window?,
    index: Int = INDEX_BIND_LAST,
) -> BindingData {
    if window?.isBound == true {
        window?.unbindFromParent() // It's important to unbind to get correct MRU data below
    }

    let root = workspace.rootTilingContainer
    let mruWindow = root.layout == .dwindle
        ? root.mostRecentDwindleWindow
        : workspace.mostRecentWindowRecursive
    guard root.layout == .dwindle, let mruWindow, let (tilingParent, targetIndex) = mruWindow.nearestAliveTilingParent() else {
        if let (tilingParent, mruIndex) = mruWindow?.nearestAliveTilingParent() {
            return BindingData(
                parent: tilingParent,
                adaptiveWeight: WEIGHT_AUTO,
                index: mruIndex + 1,
            )
        }
        return BindingData(parent: root, adaptiveWeight: WEIGHT_AUTO, index: index)
    }

    let orientation = preferredDwindleOrientation(for: mruWindow, in: workspace)

    return bindingDataBySplittingDwindleTarget(
        root: root,
        targetNode: tilingParent.children[targetIndex],
        orientation: orientation,
        newWindowGoesFirst: index == 0,
    )
}

// Split the window under the pointer; the pointer position selects the side.
@MainActor
func unbindAndGetBindingDataForDwindleDrop(
    _ workspace: Workspace,
    window: Window,
    targetWindow: Window?,
    dropPoint: Point,
) -> BindingData {
    if window.isBound {
        window.unbindFromParent()
    }

    let root = workspace.rootTilingContainer
    guard root.layout == .dwindle,
          let targetWindow,
          targetWindow != window,
          targetWindow.nodeWorkspace == workspace,
          let (tilingParent, targetIndex) = targetWindow.nearestAliveTilingParent()
    else {
        return BindingData(parent: root, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }

    let targetRect = preferredDwindleRect(for: targetWindow, in: workspace)
    let orientation: Orientation = targetRect.width > targetRect.height ? .h : .v
    let newWindowGoesFirst = dropPoint.getProjection(orientation) < targetRect.center.getProjection(orientation)

    return bindingDataBySplittingDwindleTarget(
        root: root,
        targetNode: tilingParent.children[targetIndex],
        orientation: orientation,
        newWindowGoesFirst: newWindowGoesFirst,
    )
}

@MainActor
private func bindingDataBySplittingDwindleTarget(
    root: TilingContainer,
    targetNode: TreeNode,
    orientation: Orientation,
    newWindowGoesFirst: Bool,
) -> BindingData {
    // Avoid an unnecessary wrapper for the first split. Keeping the marker on
    // the root also lets subsequent insertions identify the workspace layout.
    if targetNode.parent === root && root.inhabitedChildren.count == 1 {
        root.changeOrientation(orientation)
        return BindingData(
            parent: root,
            adaptiveWeight: WEIGHT_AUTO,
            index: newWindowGoesFirst ? 0 : INDEX_BIND_LAST,
        )
    }

    let previousBinding = targetNode.unbindFromParent()
    let split = TilingContainer(
        parent: previousBinding.parent,
        adaptiveWeight: previousBinding.adaptiveWeight,
        orientation,
        .tiles,
        index: previousBinding.index,
    )
    targetNode.bind(
        to: split,
        adaptiveWeight: WEIGHT_AUTO,
        index: newWindowGoesFirst ? INDEX_BIND_LAST : 0,
    )
    return BindingData(
        parent: split,
        adaptiveWeight: WEIGHT_AUTO,
        index: newWindowGoesFirst ? 0 : INDEX_BIND_LAST,
    )
}

@MainActor
private func preferredDwindleOrientation(for window: Window, in workspace: Workspace) -> Orientation {
    if let rect = window.lastAppliedLayoutVirtualRect {
        return rect.width > rect.height ? .h : .v
    }

    guard let parent = window.parent as? TilingContainer else {
        let rect = workspace.workspaceMonitorInfo.visibleRectPaddedByOuterGaps
        return rect.width > rect.height ? .h : .v
    }

    // Before the first layout pass, approximate the leaf as half of its parent.
    if parent.children.count > 1 {
        return parent.orientation.opposite
    }

    let rect = parent.lastAppliedLayoutVirtualRect ?? workspace.workspaceMonitorInfo.visibleRectPaddedByOuterGaps
    return rect.width > rect.height ? .h : .v
}

@MainActor
private func preferredDwindleRect(for window: Window, in workspace: Workspace) -> Rect {
    window.lastAppliedLayoutVirtualRect
        ?? window.lastAppliedLayoutPhysicalRect
        ?? (window.parent as? TilingContainer)?.lastAppliedLayoutVirtualRect
        ?? workspace.workspaceMonitorInfo.visibleRectPaddedByOuterGaps
}

extension TilingContainer {
    fileprivate var mostRecentDwindleWindow: Window? {
        switch mostRecentInhabitedChild?.tilingTreeNodeCasesOrDie() {
            case .window(let window): window
            case .tilingContainer(let container): container.mostRecentDwindleWindow
            case nil: nil
        }
    }

    /// Rebuilds an existing root as the same binary spiral produced by opening
    /// the windows one at a time in dwindle layout.
    @MainActor
    func enableDwindleLayout() -> Bool {
        guard isRootContainer, let workspace = parent as? Workspace else { return false }

        let windows = allLeafWindowsRecursive
        let previousMru = mostRecentWindowRecursive
        for window in windows {
            window.unbindFromParent()
        }
        for child in children {
            child.unbindFromParent()
        }

        layout = .dwindle
        for window in windows {
            let data = unbindAndGetBindingDataForNewTilingWindow(workspace, window: nil)
            window.bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
        }
        previousMru?.markAsMostRecentChild()
        return true
    }

    /// Leaves dwindle mode by flattening its binary containers back into the
    /// root, matching the traditional tiles/accordion tree shape.
    @MainActor
    func disableDwindleLayout(to targetLayout: Layout) {
        check(isRootContainer && layout == .dwindle && targetLayout != .dwindle)

        let windows = allLeafWindowsRecursive
        let previousMru = mostRecentWindowRecursive
        for window in windows {
            window.unbindFromParent()
        }
        for child in children {
            child.unbindFromParent()
        }

        layout = targetLayout
        for window in windows {
            window.bind(to: self, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        }
        previousMru?.markAsMostRecentChild()
    }
}
