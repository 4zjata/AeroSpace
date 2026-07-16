@testable import AppBundle
import Common
import XCTest

@MainActor
final class ScratchpadTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        scratchpadPrevWorkspaces.removeAll()
    }

    func testParseScratchpadCommands() {
        testParseSingleCommandSucc("toggle-scratchpad", ToggleScratchpadCmdArgs())
        testParseSingleCommandSucc("toggle-scratchpad --scratchpad-id term", ToggleScratchpadCmdArgs(scratchpadId: "term"))
        testParseSingleCommandSucc("move-node-to-scratchpad", MoveNodeToScratchpadCmdArgs())
        testParseSingleCommandSucc("move-node-to-scratchpad --scratchpad-id note", MoveNodeToScratchpadCmdArgs(scratchpadId: "note"))
    }

    func testToggleScratchpad_showsAndHides() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        assertEquals(focus.workspace.name, "a")

        // First toggle shows scratchpad_default on the focused monitor
        let result1 = await parseCommand("toggle-scratchpad").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result1.exitCode.rawValue, 0)
        assertEquals(focus.workspace.name, "scratchpad_default")

        // Second toggle hides scratchpad_default and restores "a"
        let result2 = await parseCommand("toggle-scratchpad").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result2.exitCode.rawValue, 0)
        assertEquals(focus.workspace.name, "a")
    }

    func testToggleScratchpad_multiMonitorSwapping() async {
        let monitor1 = testMonitor(id: 1, rect: Rect(topLeftX: 0, topLeftY: 0, width: 800, height: 600))
        let monitor2 = testMonitor(id: 2, rect: Rect(topLeftX: 1000, topLeftY: 0, width: 800, height: 600))
        testMonitors = [monitor1, monitor2]

        // Place visible workspaces
        _ = monitor1.setActiveWorkspace(Workspace.get(byName: "a"))
        _ = monitor2.setActiveWorkspace(Workspace.get(byName: "b"))
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        assertEquals(focus.workspace.name, "a")

        // 1. Show scratchpad on monitor 1
        _ = await parseCommand("toggle-scratchpad --scratchpad-id pad").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "scratchpad_pad")
        assertEquals(monitor1.activeWorkspace.name, "scratchpad_pad")
        assertEquals(monitor2.activeWorkspace.name, "b")

        // 2. Focus monitor 2
        assertTrue(Workspace.get(byName: "b").focusWorkspace())
        assertEquals(focus.workspace.name, "b")

        // 3. Show scratchpad on monitor 2 -> should release it from monitor 1 (restoring "a") and show on monitor 2
        _ = await parseCommand("toggle-scratchpad --scratchpad-id pad").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "scratchpad_pad")
        assertEquals(monitor1.activeWorkspace.name, "a")
        assertEquals(monitor2.activeWorkspace.name, "scratchpad_pad")

        // 4. Hide scratchpad on monitor 2 -> should restore "b"
        _ = await parseCommand("toggle-scratchpad --scratchpad-id pad").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "b")
        assertEquals(monitor1.activeWorkspace.name, "a")
        assertEquals(monitor2.activeWorkspace.name, "b")
    }

    func testMoveNodeToScratchpad() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        let window = Workspace.get(byName: "a").rootTilingContainer.apply {
            TestWindow.new(id: 123, parent: $0)
        }
        _ = window.focusWindow()
        assertEquals(focus.windowOrNil?.windowId, 123)

        // Move to scratchpad_default
        _ = await parseCommand("move-node-to-scratchpad").cmdOrDie.run(.defaultEnv, .emptyStdin)

        // The window should now be in scratchpad_default
        assertEquals(window.nodeWorkspace?.name, "scratchpad_default")
        assertEquals(focus.workspace.name, "a") // current workspace remains focused
    }

    func testListWorkspaces_excludesScratchpadsByDefault() async {
        _ = Workspace.get(byName: "scratchpad_mypad")
        _ = Workspace.get(byName: "a")

        let cmdArgsNormal = parseCommand("list-workspaces --all").cmdArgsOrDie as! ListWorkspacesCmdArgs
        let resultNormal = ListWorkspacesCommand(args: cmdArgsNormal).run(.defaultEnv, .emptyStdin)
        // Verify output doesn't contain scratchpad_mypad
        XCTAssertFalse(resultNormal.stdout.contains("scratchpad_mypad"))

        let cmdArgsWithScratchpad = parseCommand("list-workspaces --all --include-scratchpads").cmdArgsOrDie as! ListWorkspacesCmdArgs
        let resultWithScratchpad = ListWorkspacesCommand(args: cmdArgsWithScratchpad).run(.defaultEnv, .emptyStdin)
        // Verify output contains scratchpad_mypad
        XCTAssertTrue(resultWithScratchpad.stdout.contains("scratchpad_mypad"))
    }
}

private func testMonitor(id: Int, rect: Rect) -> Monitor {
    MonitorImpl(
        name: "test-monitor-\(id)",
        rect: rect,
        visibleRect: rect
    )
}
