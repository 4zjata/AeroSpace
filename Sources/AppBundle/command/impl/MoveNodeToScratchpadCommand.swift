import Common

struct MoveNodeToScratchpadCommand: Command {
    let args: MoveNodeToScratchpadCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        let scratchpadId = args.scratchpadId ?? "default"
        let scratchpadWsName = "scratchpad_" + scratchpadId
        let targetWorkspace = Workspace.get(byName: scratchpadWsName)
        return moveWindowToWorkspace(window, targetWorkspace, io, focusFollowsWindow: false, failIfNoop: false)
    }
}
