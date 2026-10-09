extension Workspace {
    @MainActor func normalizeContainers() {
        rootTilingContainer.unbindEmptyAndAutoFlatten() // Beware! rootTilingContainer may change after this line of code
        if config.enableNormalizationOppositeOrientationForNestedContainers && rootTilingContainer.layout != .dwindle {
            rootTilingContainer.normalizeOppositeOrientationForNestedContainers()
        }
    }
}

extension TilingContainer {
    @MainActor fileprivate func unbindEmptyAndAutoFlatten() {
        if let child = children.singleOrNil(), config.enableNormalizationFlattenContainers && (child is TilingContainer || !isRootContainer) {
            if isRootContainer, layout == .dwindle, let child = child as? TilingContainer {
                let grandchildren = child.children
                let mru = child.mostRecentChild
                child.unbindFromParent()
                changeOrientation(child.orientation)
                for grandchild in grandchildren {
                    let data = grandchild.unbindFromParent()
                    grandchild.bind(to: self, adaptiveWeight: data.adaptiveWeight, index: INDEX_BIND_LAST)
                }
                mru?.markAsMostRecentChild()
                unbindEmptyAndAutoFlatten()
                return
            }
            child.unbindFromParent()
            let mru = parent?.mostRecentChild
            let previousBinding = unbindFromParent()
            child.bind(to: previousBinding.parent, adaptiveWeight: previousBinding.adaptiveWeight, index: previousBinding.index)
            (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
            if mru != self {
                mru?.markAsMostRecentChild()
            } else {
                child.markAsMostRecentChild()
            }
        } else {
            for child in children {
                (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
            }
            if children.isEmpty && !isRootContainer {
                unbindFromParent()
            }
        }
    }
}
