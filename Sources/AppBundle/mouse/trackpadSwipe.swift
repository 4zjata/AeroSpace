import AppKit
import Common

private nonisolated(unsafe) var eventTapPort: CFMachPort? = nil

private func swipeLog(_ msg: String) {
    let file = "/tmp/aerospace-swipe.log"
    let timestamp = Date().description
    let line = "[\(timestamp)] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if let fileHandle = FileHandle(forWritingAtPath: file) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        } else {
            try? line.write(toFile: file, atomically: true, encoding: .utf8)
        }
    }
}

@MainActor
public func startTrackpadSwipeListener() {
    let mask: CGEventMask = (1 << 29) // NSEvent.EventType.gesture is 29
    swipeLog("Starting trackpad swipe listener with mask \(mask)")
    
    let callback: CGEventTapCallBack = { proxy, type, event, refcon in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            swipeLog("Event tap disabled, re-enabling")
            if let port = unsafe eventTapPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard type.rawValue == 29 else { return Unmanaged.passUnretained(event) }
        
        if let nsEvent = NSEvent(cgEvent: event) {
            let touches = nsEvent.allTouches()
            if !touches.isEmpty {
                DispatchQueue.main.async {
                    processSwipeTouches(touches)
                }
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    let handle = unsafe CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: mask,
        callback: callback,
        userInfo: nil
    )
    
    guard let handle else {
        swipeLog("Failed to create swipe CGEventTap")
        return
    }
    
    swipeLog("CGEventTap created successfully")
    unsafe eventTapPort = handle
    CGEvent.tapEnable(tap: handle, enable: true)
    
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, handle, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
    swipeLog("CGEventTap added to runloop")
}

private struct GestureState {
    enum PhaseState {
        case idle
        case began
        case fired
    }
    var state: PhaseState = .idle
    var startX: CGFloat = 0.0
    var startY: CGFloat = 0.0
    var activeTouchIdentities: Set<AnyHashable> = []
}

@MainActor
private var gestureState = GestureState()

@MainActor
private func processSwipeTouches(_ touches: Set<NSTouch>) {
    let activeTouches = touches.filter { touch in
        touch.phase == .began || touch.phase == .moved || touch.phase == .stationary
    }
    
    let requiredFingerCount = 3
    
    swipeLog("processSwipeTouches active = \(activeTouches.count) state = \(gestureState.state)")
    
    if activeTouches.count != requiredFingerCount {
        gestureState.state = .idle
        gestureState.activeTouchIdentities.removeAll()
        return
    }
    
    let touchIdentities = Set(activeTouches.map { AnyHashable($0.identity as! NSObject) })
    
    let sumX = activeTouches.reduce(0.0) { $0 + $1.normalizedPosition.x }
    let avgX = sumX / CGFloat(activeTouches.count)
    
    let sumY = activeTouches.reduce(0.0) { $0 + $1.normalizedPosition.y }
    let avgY = sumY / CGFloat(activeTouches.count)
    
    switch gestureState.state {
    case .idle:
        gestureState.state = .began
        gestureState.startX = avgX
        gestureState.startY = avgY
        gestureState.activeTouchIdentities = touchIdentities
        swipeLog("Gesture began at avgX = \(avgX), avgY = \(avgY)")
        
    case .began:
        if gestureState.activeTouchIdentities != touchIdentities {
            gestureState.startX = avgX
            gestureState.startY = avgY
            gestureState.activeTouchIdentities = touchIdentities
            return
        }
        
        let dx = avgX - gestureState.startX
        let dy = avgY - gestureState.startY
        let threshold: CGFloat = 0.12 // Responsive threshold (12% of trackpad width)
        
        if abs(dx) > abs(dy) {
            if dx > threshold {
                swipeLog("Trigger workspace next (dx = \(dx))")
                switchToWorkspace(isNext: true)
                gestureState.state = .fired
            } else if dx < -threshold {
                swipeLog("Trigger workspace prev (dx = \(dx))")
                switchToWorkspace(isNext: false)
                gestureState.state = .fired
            }
        } else {
            if dy > threshold {
                swipeLog("Trigger scratchpad open (dy = \(dy))")
                openScratchpad()
                gestureState.state = .fired
            } else if dy < -threshold {
                swipeLog("Trigger scratchpad close (dy = \(dy))")
                closeScratchpad()
                gestureState.state = .fired
            }
        }
        
    case .fired:
        break
    }
}

@MainActor
private func switchToWorkspace(isNext: Bool) {
    Task { @MainActor in
        do {
            try await runLightSession(.hotkeyBinding, .forceRun) {
                // Start from the workspace on the monitor under the cursor,
                // not the globally focused workspace. This way swiping on the
                // laptop monitor starts from workspace 1, even if workspace 2
                // on the external monitor has keyboard focus.
                let currentWs = mouseLocation.monitorApproximation.activeWorkspace
                // All workspaces except scratchpads, in keyboard order: 1-9 then 0
                let allWorkspaces = Workspace.all
                    .filter { !$0.isScratchpad }
                    .sorted { a, b in
                        let aIsZero = a.name == "0"
                        let bIsZero = b.name == "0"
                        if aIsZero && !bIsZero { return false } // 0 goes to end
                        if !aIsZero && bIsZero { return true }
                        return a.name < b.name
                    }
                guard !allWorkspaces.isEmpty else {
                    swipeLog("switchToWorkspace: no workspaces found")
                    return
                }
                let currentIdx = allWorkspaces.firstIndex(where: { $0.name == currentWs.name }) ?? 0
                // No wrap-around: stop at first (1) and last (0)
                let nextIdx: Int
                if isNext {
                    nextIdx = max(0, currentIdx - 1)
                } else {
                    nextIdx = min(allWorkspaces.count - 1, currentIdx + 1)
                }
                let workspace = allWorkspaces[nextIdx]
                swipeLog("switchToWorkspace: isNext=\(isNext) currentWs=\(currentWs.name) -> \(workspace.name)")
                if workspace.name != currentWs.name {
                    if !workspace.isVisible && config.workspaceToMonitorForceAssignment[workspace.name] == nil {
                        let focusedMonitor = currentWs.workspaceMonitor
                        let monitorTargetOriginal = workspace.workspaceMonitor
                        if focusedMonitor.setActiveWorkspace(workspace) {
                            currentWs.assignedMonitorPoint = monitorTargetOriginal.rect.topLeftCorner
                        }
                    }
                    let ok = workspace.focusWorkspace()
                    swipeLog("switchToWorkspace: focusWorkspace=\(ok)")
                }
            }
        } catch {
            swipeLog("switchToWorkspace: error: \(error)")
        }
    }
}

@MainActor
private func openScratchpad() {
    Task { @MainActor in
        do {
            try await runLightSession(.hotkeyBinding, .forceRun) {
                let scratchpadId = config.workspaceSwipeScratchpad
                let scratchpadWsName = "scratchpad_" + scratchpadId
                let wsTarget = Workspace.get(byName: scratchpadWsName)
                
                let focusedWs = focus.workspace
                let focusedMonitor = focusedWs.workspaceMonitor
                
                if wsTarget.isVisible && wsTarget.workspaceMonitor.rect.topLeftCorner == focusedMonitor.rect.topLeftCorner {
                    // Already visible on current monitor, do nothing
                    swipeLog("openScratchpad: already open")
                    return
                }
                
                // Run ToggleScratchpadCommand to show it
                var args = ToggleScratchpadCmdArgs(rawArgs: [])
                args.scratchpadId = scratchpadId
                let cmd = ToggleScratchpadCommand(args: args)
                _ = await cmd.run(CmdEnv.defaultEnv, CmdIoImpl.emptyStdinIgnoringOut)
            }
        } catch {
            swipeLog("openScratchpad: error: \(error)")
        }
    }
}

@MainActor
private func closeScratchpad() {
    Task { @MainActor in
        do {
            try await runLightSession(.hotkeyBinding, .forceRun) {
                let scratchpadId = config.workspaceSwipeScratchpad
                let scratchpadWsName = "scratchpad_" + scratchpadId
                let wsTarget = Workspace.get(byName: scratchpadWsName)
                
                let focusedWs = focus.workspace
                let focusedMonitor = focusedWs.workspaceMonitor
                
                if wsTarget.isVisible && wsTarget.workspaceMonitor.rect.topLeftCorner == focusedMonitor.rect.topLeftCorner {
                    // Visible on current monitor, toggle it to hide
                    var args = ToggleScratchpadCmdArgs(rawArgs: [])
                    args.scratchpadId = scratchpadId
                    let cmd = ToggleScratchpadCommand(args: args)
                    _ = await cmd.run(CmdEnv.defaultEnv, CmdIoImpl.emptyStdinIgnoringOut)
                } else {
                    swipeLog("closeScratchpad: not open here")
                }
            }
        } catch {
            swipeLog("closeScratchpad: error: \(error)")
        }
    }
}
