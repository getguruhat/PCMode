import AppKit
import ServiceManagement
import SwiftUI

final class WinSettings: ObservableObject {
    private let defaults: UserDefaults
    var onChange: (() -> Void)?
    @Published var deleteEnabled: Bool { didSet { save() } }
    @Published var cutEnabled: Bool { didSet { save() } }
    @Published var deleteKey: DeleteKey { didSet { save() } }
    @Published var switcherEnabled: Bool { didSet { save() } }
    @Published var launchAtLogin: Bool { didSet { updateLaunchAtLogin() } }
    @Published var menuBarIconEnabled: Bool { didSet { save() } }
    @Published var launchAtLoginMessage = ""
    @Published var permissionMessage = "Checking permissions…"
    private var updatingLaunchAtLogin = false
    var permissionsReady: Bool { permissionMessage == "Ready" }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["DeleteEnabled": true, "CutEnabled": true, "SwitcherEnabled": true,
                                     "LaunchAtLogin": true])
        deleteEnabled = defaults.bool(forKey: "DeleteEnabled")
        cutEnabled = defaults.bool(forKey: "CutEnabled")
        let savedDeleteKey = DeleteKey(rawValue: defaults.string(forKey: "DeleteKey") ?? "") ?? .rewind
        deleteKey = DeleteKey.menuCases.contains(savedDeleteKey) ? savedDeleteKey : .rewind
        switcherEnabled = defaults.bool(forKey: "SwitcherEnabled")
        defaults.register(defaults: ["MenuBarIconEnabled": true])
        menuBarIconEnabled = defaults.bool(forKey: "MenuBarIconEnabled")
        launchAtLogin = defaults.bool(forKey: "LaunchAtLogin")
        defaults.removeObject(forKey: "SystemEventsFallback")
        if SMAppService.mainApp.status != .enabled {
            launchAtLogin = true
            updateLaunchAtLogin()
        } else {
            refreshLaunchAtLoginMessage()
        }
    }
    private func save() {
        defaults.set(deleteEnabled, forKey: "DeleteEnabled")
        defaults.set(cutEnabled, forKey: "CutEnabled")
        defaults.set(deleteKey.rawValue, forKey: "DeleteKey")
        defaults.set(switcherEnabled, forKey: "SwitcherEnabled")
        defaults.set(menuBarIconEnabled, forKey: "MenuBarIconEnabled")
        onChange?()
    }
    private func updateLaunchAtLogin() {
        guard !updatingLaunchAtLogin else { return }
        updatingLaunchAtLogin = true
        defer { updatingLaunchAtLogin = false }
        defaults.set(launchAtLogin, forKey: "LaunchAtLogin")
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status == .notRegistered { try SMAppService.mainApp.register() }
                if SMAppService.mainApp.status != .enabled { try installLaunchAgent() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
                removeLaunchAgent()
            }
            refreshLaunchAtLoginMessage()
        } catch {
            launchAtLogin = false
            defaults.set(false, forKey: "LaunchAtLogin")
            launchAtLoginMessage = "Could not update Login Items: \(error.localizedDescription)"
        }
    }

    private func installLaunchAgent() throws {
        let agents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let plistURL = agents.appendingPathComponent("com.andre.pcmode.plist")
        let executable = Bundle.main.executableURL?.path ?? "/Applications/PCMode.app/Contents/MacOS/PCMode"
        let plist: [String: Any] = [
            "Label": "com.andre.pcmode",
            "ProgramArguments": [executable, "--background"],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        (plist as NSDictionary).write(to: plistURL, atomically: true)
    }

    private func removeLaunchAgent() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.andre.pcmode.plist")
        try? FileManager.default.removeItem(at: url)
    }
    private func refreshLaunchAtLoginMessage() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
            launchAtLoginMessage = ""
        case .requiresApproval:
            launchAtLogin = false
            launchAtLoginMessage = "Allow PC Mode in System Settings → General → Login Items."
        case .notFound:
            launchAtLogin = false
            launchAtLoginMessage = "Move PC Mode to Applications to enable this."
        default:
            launchAtLogin = false
            launchAtLoginMessage = ""
        }
    }
}

private struct SettingsIcon: View {
    let name: String
    var body: some View {
        let icon = Bundle.main.url(forResource: name, withExtension: "png")
            .flatMap(NSImage.init(contentsOf:)) ?? NSImage()
        Image(nsImage: icon)
            .resizable()
            .scaledToFill()
            .frame(width: 48, height: 48)
            .scaleEffect(1.18)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .frame(width: 48, alignment: .center)
    }
}

private struct SettingsSystemIcon: View {
    let name: String
    var color: Color = .blue
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 48, height: 48)
    }
}

final class SettingsWindowController {
    private var window: NSWindow?
    func show(settings: WinSettings, updates: UpdateChecker, requestPermissions: @escaping () -> Void) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 466, height: 570),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "PC Mode"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsWindowView(settings: settings, updates: updates, requestPermissions: requestPermissions))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsWindowView: View {
    @ObservedObject var settings: WinSettings
    @ObservedObject var updates: UpdateChecker
    let requestPermissions: () -> Void

    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Finder").font(.headline)
                HStack(alignment: .top, spacing: 12) {
                    SettingsSystemIcon(name: "trash.fill")
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Delete key moves items to Trash", isOn: $settings.deleteEnabled)
                        HStack(spacing: 10) {
                            Text("Shortcut key")
                            Picker("Shortcut key", selection: $settings.deleteKey) {
                                ForEach(DeleteKey.menuCases) { key in
                                    Label(key.menuTitle, systemImage: key.symbolName)
                                        .tag(key)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 95)
                            .disabled(!settings.deleteEnabled)
                        }
                        Text("Uses this key instead of its normal Finder action.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .top, spacing: 12) {
                    SettingsIcon(name: "CutSettingIcon")
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Cut and move with ⌘X / ⌘V", isOn: $settings.cutEnabled)
                        Text("Select files, press ⌘X, then open a destination folder and press ⌘V.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                Text("Windows").font(.headline)
                HStack(alignment: .top, spacing: 12) {
                    SettingsIcon(name: "WindowSettingIcon")
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Switch individual windows with ⌘Tab", isOn: $settings.switcherEnabled)
                        Text("Switch between individual windows, including minimized and hidden windows.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("PC Mode").font(.headline)
                    HStack(alignment: .center, spacing: 12) {
                        SettingsSystemIcon(name: "menubar.rectangle")
                        Toggle("Show PC Mode in the menu bar", isOn: $settings.menuBarIconEnabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Color.clear.frame(height: 4)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Permissions")
                            .font(.headline)
                        HStack(spacing: 12) {
                            Button("Manage", action: requestPermissions)
                            ZStack {
                                Circle()
                                    .fill(settings.permissionsReady ? Color.green : Color.red)
                                Image(systemName: settings.permissionsReady ? "checkmark" : "exclamationmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 16, height: 16)
                            .fixedSize()
                            Text(settings.permissionMessage)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.trailing, 24)
                    Spacer(minLength: 0)
                }
                .padding(.top, -18)
                Spacer(minLength: 8)
                HStack {
                    Spacer()
                    Button("Quit PC Mode") {
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: [.command])
                    Spacer()
                }
            }
            .padding(18)
            .offset(y: -8)
            .tabItem { Text("Settings") }

            VStack(spacing: 14) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().scaledToFit().frame(width: 140, height: 140)
                Text("PC Mode").font(.title).bold()
                Text("Version \(updates.currentVersion)").foregroundStyle(.secondary)
                if let update = updates.available {
                    Link("Download PC Mode \(update.version) ›", destination: update.page)
                }
                Text("A GuruHat open-source tool").font(.headline)
                Text("Put on your PC hat.").foregroundStyle(.secondary)
                Divider().padding(.vertical, 4)
                HStack(spacing: 12) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://github.com/getguruhat")!)
                    } label: {
                        Label("View on GitHub ↗", systemImage: "chevron.left.forwardslash.chevron.right")
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.28)))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://www.paypal.com/donate/?hosted_button_id=FHGYWD46722JS")!)
                    } label: {
                        Label("Support GuruHat", systemImage: "heart.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.blue.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text("Thank you for using PC Mode!").font(.caption).foregroundStyle(.secondary)
                Text("Windows is a trademark of Microsoft.\nGuruHat is not affiliated with or endorsed by Microsoft.")
                    .multilineTextAlignment(.center).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .tabItem { Text("About") }
        }
        .padding(12)
        .frame(width: 466, height: 570)
    }
}
