import AppKit
import Common

/// Returns where a new tiling window should be bound. In dwindle layout, the
/// focused leaf is replaced with a binary split. Other layouts retain the
/// traditional AeroSpace behavior of inserting next to the focused window.
///
/// This function is unsafe by design: when `window` is non-nil, it leaves the
/// window unbound so the caller can bind it using the returned data.
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
        ? root.mostRecentWindowRecursive
        : workspace.mostRecentWindowRecursive
    guard root.layout == .dwindle, let mruWindow, let tilingParent = mruWindow.parent as? TilingContainer else {
        if let mruWindow, let tilingParent = mruWindow.parent as? TilingContainer {
            return BindingData(
                parent: tilingParent,
                adaptiveWeight: WEIGHT_AUTO,
                index: mruWindow.ownIndex.orDie() + 1,
            )
        }
        return BindingData(parent: root, adaptiveWeight: WEIGHT_AUTO, index: index)
    }

    let newWindowGoesFirst = index == 0
    let orientation = preferredDwindleOrientation(for: mruWindow, in: workspace)

    // Avoid an unnecessary wrapper for the first split. Keeping the marker on
    // the root also lets subsequent insertions identify the workspace layout.
    if tilingParent === root && root.children.count == 1 {
        root.changeOrientation(orientation)
        return BindingData(
            parent: root,
            adaptiveWeight: WEIGHT_AUTO,
            index: newWindowGoesFirst ? 0 : INDEX_BIND_LAST,
        )
    }

    let previousBinding = mruWindow.unbindFromParent()
    let split = TilingContainer(
        parent: previousBinding.parent,
        adaptiveWeight: previousBinding.adaptiveWeight,
        orientation,
        .tiles,
        index: previousBinding.index,
    )
    mruWindow.bind(
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
        let rect = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        return rect.width > rect.height ? .h : .v
    }

    // During startup the tree is built before its first layout pass. A leaf
    // created by the previous binary split occupies half of its parent, so the
    // opposite orientation is the best deterministic approximation.
    if parent.children.count > 1 {
        return parent.orientation.opposite
    }

    let rect = parent.lastAppliedLayoutVirtualRect ?? workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
    return rect.width > rect.height ? .h : .v
}

extension TilingContainer {
    /// Rebuilds an existing root as the same binary spiral produced by opening
    /// the windows one at a time in dwindle layout.
    @MainActor
    func enableDwindleLayout() -> Bool {
        guard isRootContainer, let workspace = parent as? Workspace else { return false }

        let windows = allLeafWindowsRecursive
        let previousMru = mostRecentWindowRecursive
        for window in windows where window.isBound {
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
        for window in windows where window.isBound {
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
