import Common
import AppKit

@MainActor
public var scratchpadPrevWorkspaces: [String: String] = [:]

struct ToggleScratchpadCommand: Command {
    let args: ToggleScratchpadCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let scratchpadId = args.scratchpadId ?? "default"
        let scratchpadWsName = "scratchpad_" + scratchpadId
        let wsTarget = Workspace.get(byName: scratchpadWsName)
        
        let focusedWs = focus.workspace
        let focusedMonitor = focusedWs.workspaceMonitor

        // Rule 1: If the scratchpad is visible on the focused monitor -> hide it
        if wsTarget.isVisible && wsTarget.workspaceMonitor.rect.topLeftCorner == focusedMonitor.rect.topLeftCorner {
            let prevWsName = scratchpadPrevWorkspaces[scratchpadId] ?? ""
            let wsPrev = Workspace.get(byName: prevWsName)
            let workspaceToFocus = (!wsPrev.isVisible || wsPrev.workspaceMonitor.rect.topLeftCorner == focusedMonitor.rect.topLeftCorner)
                ? wsPrev
                : getStubWorkspace(for: focusedMonitor)
            scratchpadPrevWorkspaces[scratchpadId] = nil
            return .from(bool: workspaceToFocus.focusWorkspace())
        }

        // Rule 2: If the scratchpad is visible on another monitor -> release it from there
        if wsTarget.isVisible {
            let targetMonitor = wsTarget.workspaceMonitor
            let prevWsName = scratchpadPrevWorkspaces[scratchpadId] ?? ""
            let wsPrev = Workspace.get(byName: prevWsName)
            let workspaceToRestore = (!wsPrev.isVisible || wsPrev.workspaceMonitor.rect.topLeftCorner == targetMonitor.rect.topLeftCorner)
                ? wsPrev
                : getStubWorkspace(for: targetMonitor)
            _ = targetMonitor.setActiveWorkspace(workspaceToRestore)
            scratchpadPrevWorkspaces[scratchpadId] = nil
        }

        // Rule 3: Show it on the focused monitor
        // Remember the currently active workspace on the focused monitor so we can restore it later
        scratchpadPrevWorkspaces[scratchpadId] = focusedWs.name
        
        _ = focusedMonitor.setActiveWorkspace(wsTarget)
        
        let focusSucceeded = wsTarget.focusWorkspace()
        if focusSucceeded {
            // Run onCreatedEmpty if the workspace is effectively empty
            if wsTarget.isEffectivelyEmpty, let scratchpadConfig = config.scratchpads[scratchpadId] {
                _ = await scratchpadConfig.onCreatedEmpty.run(env, io)
            }
        }
        return .from(bool: focusSucceeded)
    }
}
