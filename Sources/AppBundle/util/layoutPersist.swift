import Foundation
import Cocoa
import CoreGraphics
import Common

struct SavedWindowState: Codable {
    let appId: String
    let appName: String
    let title: String
    let workspace: String
    let isFloating: Bool
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

@MainActor
func getWindowTitlesMap() -> [UInt32: String] {
    var map: [UInt32: String] = [:]
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    if let cfArray = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [CFDictionary] {
        for elem in cfArray {
            let dict = elem as NSDictionary
            let windowId = (dict[kCGWindowNumber] as? NSNumber)?.uint32Value ?? 0
            let title = (dict[kCGWindowName] as? String) ?? ""
            map[windowId] = title
        }
    }
    return map
}

@MainActor
public func saveDebugWindowStates() {
    let titlesMap = getWindowTitlesMap()
    var saved: [SavedWindowState] = []
    
    let path = debugLayoutFilePath()
    
    for window in MacWindow.allWindowsMap.values {
        guard let appId = window.app.rawAppBundleId else { continue }
        let title = titlesMap[window.windowId] ?? ""
        let workspaceName = window.nodeWorkspace?.name ?? ""
        
        let rect = window.macApp.getAxRectForTermination(window.windowId) ?? Rect(topLeftX: 0, topLeftY: 0, width: 0, height: 0)
        
        saved.append(SavedWindowState(
            appId: appId,
            appName: window.app.name ?? "",
            title: title,
            workspace: workspaceName,
            isFloating: window.isFloating,
            x: rect.topLeftX,
            y: rect.topLeftY,
            width: rect.width,
            height: rect.height
        ))
    }
    
    if let data = try? JSONEncoder().encode(saved) {
        try? data.write(to: URL(filePath: path))
        print("[aerospace-debug] Saved \(saved.count) window states to \(path)")
    }
}

@MainActor
public func restoreDebugWindowStates() {
    let path = debugLayoutFilePath()
    guard let data = try? Data(contentsOf: URL(filePath: path)),
          let saved = try? JSONDecoder().decode([SavedWindowState].self, from: data),
          !saved.isEmpty else {
        return
    }
    
    print("[aerospace-debug] Attempting to restore \(saved.count) window states...")
    
    let titlesMap = getWindowTitlesMap()
    var activeWindows = Array(MacWindow.allWindowsMap.values)
    
    for state in saved {
        guard let index = activeWindows.firstIndex(where: { win in
            guard let appId = win.app.rawAppBundleId, appId == state.appId else { return false }
            let title = titlesMap[win.windowId] ?? ""
            return title == state.title || state.title.isEmpty
        }) else {
            continue
        }
        
        let window = activeWindows.remove(at: index)
        let workspace = Workspace.get(byName: state.workspace)
        
        if state.isFloating {
            _ = window.bindAsFloatingWindow(to: workspace)
            window.setAxFrame(CGPoint(x: state.x, y: state.y), CGSize(width: state.width, height: state.height))
            print("[aerospace-debug] Restored \(window.app.name ?? "App") as FLOATING on workspace \(state.workspace)")
        } else {
            _ = window.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            print("[aerospace-debug] Restored \(window.app.name ?? "App") as TILING on workspace \(state.workspace)")
        }
    }
}

// SA-07: Use a user-private directory instead of world-writable /tmp/
private func debugLayoutFilePath() -> String {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("AeroSpace")
    try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    return appSupport.appendingPathComponent("debug-layout.json").path
}
