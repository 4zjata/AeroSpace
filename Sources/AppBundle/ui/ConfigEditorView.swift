import SwiftUI
import Common

public struct ConfigEditorView: View {
    @State private var windows: [WindowInfo] = []
    @State private var selectedWindow: WindowInfo? = nil
    @State private var matchApp = true
    @State private var matchTitle = false
    @State private var titlePattern = ""
    @State private var statusMessage = ""
    
    struct WindowInfo: Identifiable, Hashable {
        let id: UInt32
        let appName: String
        let appId: String
        let title: String
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select an active window to configure:")
                .font(.headline)
            
            List(windows, id: \.id, selection: $selectedWindow) { window in
                HStack {
                    VStack(alignment: .leading) {
                        Text(window.appName)
                            .font(.body)
                        Text(window.title.isEmpty ? "(No Title)" : window.title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(window.appId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .tag(window)
            }
            .frame(minHeight: 200)
            
            if let selected = selectedWindow {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Configure floating rule for: \(selected.appName)")
                        .font(.subheadline)
                        .bold()
                    
                    Toggle("Match entire application (\(selected.appId))", isOn: $matchApp)
                    
                    Toggle("Match specific window title", isOn: $matchTitle)
                        .onChange(of: matchTitle) { val in
                            if val && titlePattern.isEmpty {
                                titlePattern = selected.title
                            }
                        }
                    
                    if matchTitle {
                        TextField("Window Title Pattern (regex)", text: $titlePattern)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    Button("Add to Config as Floating") {
                        addRule(selected)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundColor(.green)
                    .font(.body)
            }
            
            HStack {
                Spacer()
                Button("Refresh Windows") {
                    refreshWindows()
                }
                Button("Close") {
                    NSApplication.shared.windows.forEach {
                        if $0.identifier?.rawValue == configEditorWindowId {
                            $0.close()
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 550, height: 500)
        .onAppear {
            refreshWindows()
        }
    }
    
    @MainActor
    private func refreshWindows() {
        Task {
            var list: [WindowInfo] = []
            for workspace in Workspace.all {
                for window in workspace.allLeafWindowsRecursive {
                    let title = (try? await window.getTitle(.nonCancellable)) ?? ""
                    list.append(WindowInfo(
                        id: window.windowId,
                        appName: window.app.name ?? "Unknown",
                        appId: window.app.rawAppBundleId ?? "",
                        title: title
                    ))
                }
            }
            self.windows = list.sorted { $0.appName < $1.appName }
        }
    }
    
    private func addRule(_ window: WindowInfo) {
        let configUrl: URL
        switch findCustomConfigUrl() {
            case .file(let url):
                configUrl = url
            case .noCustomConfigExists:
                configUrl = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
                if !FileManager.default.fileExists(atPath: configUrl.path) {
                    try? "".write(to: configUrl, atomically: true, encoding: .utf8)
                }
            case .ambiguousConfigError:
                statusMessage = "Error: Ambiguous configs found!"
                return
        }
        
        var ruleText = "\n[[on-window-detected]]\n"
        if matchApp {
            ruleText += "if.app-id = '\(window.appId)'\n"
        }
        if matchTitle {
            let escapedPattern = titlePattern.replacingOccurrences(of: "'", with: "\\'")
            ruleText += "if.window-title-regex-substring = '\(escapedPattern)'\n"
        }
        ruleText += "run = 'layout floating'\n"
        
        do {
            let fileHandle = try FileHandle(forWritingTo: configUrl)
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            if let data = ruleText.data(using: .utf8) {
                fileHandle.write(data)
                statusMessage = "Successfully added rule to \(configUrl.lastPathComponent)!"
                
                Task.startUnstructured { @MainActor in
                    if let _: RunSessionGuard = .isServerEnabled {
                        let args = ReloadConfigCmdArgs(rawArgs: []).copy(\.warningsAsErrors, false)
                        _ = await reloadConfig_nonCancellable(args: args)
                    }
                }
            }
        } catch {
            statusMessage = "Failed to write to config: \(error.localizedDescription)"
        }
    }
}

public let configEditorWindowId = "\(aeroSpaceAppName).configEditor"

@MainActor
public func getConfigEditorWindow() -> some Scene {
    SwiftUI.Window("AeroSpace Config Editor", id: configEditorWindowId) {
        ConfigEditorView()
            .onAppear {
                NSApp.setActivationPolicy(.accessory)
                NSApplication.shared.windows.forEach {
                    if $0.identifier?.rawValue == configEditorWindowId {
                        $0.level = .floating
                    }
                }
            }
    }
    .windowResizability(.contentSize)
}
