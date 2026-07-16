import AppKit

@MainActor private var focusFollowsMouseMonitor: Any? = nil
@MainActor private var focusFollowsTask: Task<(), any Error>? = nil

@MainActor func syncFocusFollowsMouse(_ config: Config) {
    if config.focusFollowsMouse.enabled == (focusFollowsMouseMonitor != nil) {
        return
    }

    if !config.focusFollowsMouse.enabled {
        NSEvent.removeMonitor(focusFollowsMouseMonitor.orDie())
        focusFollowsMouseMonitor = nil
        focusFollowsTask?.cancel()
        focusFollowsTask = nil
        return
    }

    // Interestingly, this callback seems to not fire when the mouse is down which is good,
    // because this is how I want it to work for windows/tabs/files dragging
    focusFollowsMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { @MainActor event in
        let location = event.locationInWindow.withYAxisFlipped
        focusFollowsTask?.cancel()
        focusFollowsTask = Task.startUnstructured { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try checkCancellation()
            // Ignores macOS menubar dropdown, but, unfortunately, it doesn't ignore non-native menu-like fake windows.
            // todo: It would be cool to somehow reuse isWindowHeuristic logic here
            if await isAxWindowUnderMouse(location) == false { return }
            try checkCancellation()
            let workspace = location.monitorApproximation.activeWorkspace
            var window: Window? = nil
            for child in workspace.floatingWindowsContainer.mruChildren {
                try checkCancellation()
                guard let child = child as? Window else { continue }
                guard let rect = try await child.getAxRect(.cancellable) else { continue }
                if rect.contains(location) {
                    window = child
                    break
                }
            }
            if window == nil {
                window = location.findWindowRecursively(in: workspace.rootTilingContainer, virtual: false, fullscreenCoversAll: true)
            }
            if let window {
                // Don't steal focus from a floating window when the cursor moves
                // to a tiling window. This prevents floating windows from
                // "disappearing" (going behind tiling windows) when the cursor
                // leaves the floating window's bounds.
                // NOTE: CGSSetWindowLevel (private API) could set other apps'
                // windows to always-on-top, but WindowServer rejects it for
                // windows not owned by the calling process.
                if !window.isFloating, let focusedWindow = focus.windowOrNil, focusedWindow.isFloating {
                    return
                }
                try await runLightSession(.focusFollowsMouse, token) {
                    _ = window.focusWindow()
                    window.nativeFocus()
                }
            }
        }
    }
}

@concurrent
private nonisolated func isAxWindowUnderMouse(_ location: CGPoint) async -> Bool? {
    let systemwide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    if unsafe AXUIElementCopyElementAtPosition(systemwide, Float(location.x), Float(location.y), &element) != .success {
        return nil
    }
    guard let element else { return nil }
    return element.get(Ax.parentWindowRecursive) != nil || element.get(Ax.roleAttr) == kAXWindowRole
}
