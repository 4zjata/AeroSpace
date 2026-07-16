import Common

private let scratchpadParserTable: [String: any ParserProtocol<ScratchpadConfig>] = [
    "on-created-empty": Parser(\.onCreatedEmpty, parseShellOfCommandsForConfig),
]

func parseScratchpadConfig(_ rawConfig: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> ScratchpadConfig {
    parseTable(rawConfig, ScratchpadConfig(), scratchpadParserTable, backtrace, &c)
}

func parseScratchpads(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [String: ScratchpadConfig] {
    guard let rawTable = raw.asDictOrNil else {
        c.errors += [expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace)]
        return [:]
    }
    var result: [String: ScratchpadConfig] = [:]
    for (scratchpadId, rawScratchpadConfig) in rawTable {
        result[scratchpadId] = parseScratchpadConfig(rawScratchpadConfig, backtrace + .key(scratchpadId), &c)
    }
    return result
}
