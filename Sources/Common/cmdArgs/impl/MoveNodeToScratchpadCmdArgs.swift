public struct MoveNodeToScratchpadCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .moveNodeToScratchpad,
        help: move_node_to_scratchpad_help_generated,
        flags: [
            "--scratchpad-id": singleValueSubArgParser(\.scratchpadId, "<name>", Result.success),
        ],
        posArgs: []
    )

    public var scratchpadId: String? = nil
}
