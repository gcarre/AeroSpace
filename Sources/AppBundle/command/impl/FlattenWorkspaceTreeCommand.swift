import AppKit
import Common

struct FlattenWorkspaceTreeCommand: Command {
    let args: FlattenWorkspaceTreeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        let workspace = target.workspace
        let root = workspace.rootTilingContainer
        if root.layout == .dwindle {
            root.disableDwindleLayout(to: .tiles)
            return .succ
        }
        let windows = root.allLeafWindowsRecursive
        for window in windows {
            window.bind(to: root, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        }
        return .succ
    }
}
