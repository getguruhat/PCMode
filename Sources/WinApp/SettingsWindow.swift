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
    @Published var permissionMessage = T("Checking permissions…")
    private var updatingLaunchAtLogin = false
    var permissionsReady: Bool { permissionMessage == T("Ready") }

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
        if SMAppService.mainApp.status != .enabled && !agentInstalled {
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
                if SMAppService.mainApp.status == .notRegistered { try? SMAppService.mainApp.register() }
                if SMAppService.mainApp.status != .enabled { try installLaunchAgent() }
            } else {
                if SMAppService.mainApp.status != .notRegistered { try? SMAppService.mainApp.unregister() }
                removeLaunchAgent()
            }
            refreshLaunchAtLoginMessage()
        } catch {
            launchAtLogin = false
            defaults.set(false, forKey: "LaunchAtLogin")
            launchAtLoginMessage = T("Could not update Login Items: {0}", error.localizedDescription)
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

    /// The launch agent PC Mode installs when macOS won't register it as a Login Item, such as
    /// for a copy that isn't signed by a developer.
    private var agentInstalled: Bool {
        FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.andre.pcmode.plist").path)
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
        case .requiresApproval where !agentInstalled:
            launchAtLogin = false
            launchAtLoginMessage = T("Allow PC Mode in System Settings → General → Login Items.")
        case .notFound where !agentInstalled:
            launchAtLogin = false
            launchAtLoginMessage = T("Move PC Mode to Applications to enable this.")
        default:
            launchAtLogin = agentInstalled
            launchAtLoginMessage = ""
        }
    }
}

/// A glossy, raised tile with a white symbol: a gradient, a bright top edge and a soft shadow
/// underneath, so it reads as a small 3D object.
private struct Icon3D: View {
    let symbol: String
    let top: Color
    let bottom: Color
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            // Gloss on the upper half.
            shape.fill(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0)], startPoint: .top, endPoint: .center))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.05), .black.opacity(0.18)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1.5)
        }
        .frame(width: 44, height: 44)
        .shadow(color: bottom.opacity(0.5), radius: 4, y: 3)
    }
}

/// Which tab the Settings window shows. (@State needs a macro plugin the command-line
/// toolchain lacks.)
final class SettingsTab: ObservableObject {
    enum Tab: String, CaseIterable { case features = "Features", general = "General", about = "About" }
    @Published var current: Tab = .features
}

final class SettingsWindowController {
    private var window: NSWindow?
    private let tab = SettingsTab()
    func show(settings: WinSettings, updates: UpdateChecker, requestPermissions: @escaping () -> Void) {
        if window == nil {
            // A hosting controller, not a hosting view: the window takes its preferred size, and
            // follows it when the tab changes the content's height.
            let hosting = NSHostingController(rootView: SettingsWindowView(settings: settings, updates: updates, tab: tab,
                                                                          requestPermissions: requestPermissions))
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.title = T("PC Mode Settings")
            window.isReleasedWhenClosed = false
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
    @ObservedObject var tab: SettingsTab
    let requestPermissions: () -> Void
    private let donationURL = URL(string: "https://www.paypal.com/donate/?hosted_button_id=FHGYWD46722JS")!
    private let helpURL = URL(string: "https://guruhat.com/apps/pcmode/help/")!

    var body: some View {
        VStack(spacing: 16) {
            tabSwitch
            switch tab.current {
            case .features: featuresTab
            case .general: generalTab
            case .about: aboutTab
            }
        }
        .padding(20)
        .frame(width: 390)
        .foregroundStyle(Theme.text)
        .background(Theme.page)
    }

    /// The same soft track and white pill as ServerHat's and AI Meter's switch.
    private var tabSwitch: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.Tab.allCases, id: \.self) { item in
                let selected = item == tab.current
                Button { tab.current = item } label: {
                    Text(T(item.rawValue))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Theme.text : Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(Capsule().fill(selected ? Theme.card : Color.clear)
                            .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 1.5, y: 0.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .frame(maxWidth: .infinity)
    }

    private func title(_ text: String) -> some View {
        Text(T(text)).font(.system(size: 13, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func hint(_ text: String) -> some View {
        Text(T(text)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(icon: some View, _ text: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                title(text)
                hint(detail)
            }
            Spacer(minLength: 8)
            Toggle(T(text), isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
    }

    private var featuresTab: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Icon3D(symbol: "trash.fill", top: Color(red: 0.45, green: 0.62, blue: 1.0), bottom: Color(red: 0.16, green: 0.30, blue: 0.86))
                VStack(alignment: .leading, spacing: 6) {
                    title("Delete key moves items to Trash")
                    HStack(spacing: 8) {
                        Text(T("Shortcut key")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Picker(T("Shortcut key"), selection: $settings.deleteKey) {
                            ForEach(DeleteKey.menuCases) { key in
                                Label(key.menuTitle, systemImage: key.symbolName).tag(key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 95)
                        .disabled(!settings.deleteEnabled)
                    }
                    hint("Uses this key instead of its normal Finder action.")
                }
                Spacer(minLength: 8)
                Toggle(T("Delete key moves items to Trash"), isOn: $settings.deleteEnabled)
                    .toggleStyle(.switch).labelsHidden()
            }
            .card(padding: 12)

            row(icon: Icon3D(symbol: "scissors", top: Color(red: 1.0, green: 0.68, blue: 0.30), bottom: Color(red: 0.93, green: 0.40, blue: 0.08)),
                "Cut and move with ⌘X / ⌘V",
                detail: "Select files, press ⌘X, then open a destination folder and press ⌘V.", isOn: $settings.cutEnabled)
                .card(padding: 12)

            row(icon: Icon3D(symbol: "macwindow.on.rectangle", top: Color(red: 0.36, green: 0.82, blue: 0.95), bottom: Color(red: 0.05, green: 0.50, blue: 0.82)),
                "Switch individual windows with ⌘Tab",
                detail: "Switch between individual windows, including minimized and hidden windows.", isOn: $settings.switcherEnabled)
                .card(padding: 12)
        }
    }

    private var generalTab: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Icon3D(symbol: "power", top: Color(red: 0.45, green: 0.88, blue: 0.55), bottom: Color(red: 0.10, green: 0.60, blue: 0.32))
                    title("Open PC Mode at login")
                    Spacer()
                    Toggle(T("Open PC Mode at login"), isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch).labelsHidden()
                }
                if !settings.launchAtLoginMessage.isEmpty {
                    Text(settings.launchAtLoginMessage).font(.system(size: 11)).foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card(padding: 12)

            HStack(spacing: 12) {
                Icon3D(symbol: "menubar.rectangle", top: Color(red: 0.72, green: 0.58, blue: 1.0), bottom: Color(red: 0.43, green: 0.27, blue: 0.85))
                title("Show PC Mode in the menu bar")
                Spacer()
                Toggle(T("Show PC Mode in the menu bar"), isOn: $settings.menuBarIconEnabled)
                    .toggleStyle(.switch).labelsHidden()
            }
            .card(padding: 12)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Icon3D(symbol: "lock.shield.fill", top: settings.permissionsReady ? Color(red: 0.45, green: 0.88, blue: 0.55) : Color(red: 1.0, green: 0.55, blue: 0.50),
                           bottom: settings.permissionsReady ? Color(red: 0.10, green: 0.60, blue: 0.32) : Color(red: 0.85, green: 0.20, blue: 0.20))
                    VStack(alignment: .leading, spacing: 2) {
                        title("Permissions")
                        Text(settings.permissionMessage)
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Button(T("Manage"), action: requestPermissions)
                        .buttonStyle(TintButtonStyle(color: Theme.accent))
                    Link(T("Not working? ›"), destination: helpURL)
                        .font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
            }
            .card(padding: 12)

            Button(T("Quit PC Mode")) { NSApp.terminate(nil) }
                .buttonStyle(TintButtonStyle(color: Theme.red))
                .keyboardShortcut("q", modifiers: [.command])
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable().scaledToFit().frame(width: 76, height: 76)
            VStack(spacing: 4) {
                Text("PC Mode").font(.title2).bold()
                Text(T("Version {0}", updates.currentVersion)).foregroundStyle(.secondary)
                if let update = updates.available {
                    Link(T("Download PC Mode {0} ›", update.version), destination: update.page)
                        .foregroundStyle(Theme.accent)
                }
                Text(T("A GuruHat open-source tool")).font(.headline)
                Text(T("Put on your PC hat.")).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 2)
            Link(destination: donationURL) {
                Label(T("Support GuruHat"), systemImage: "heart.fill").frame(maxWidth: .infinity)
            }
            .foregroundStyle(Theme.accent)
            Text(T("Donations keep GuruHat apps free. Thank you!"))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Link("guruhat.com", destination: URL(string: "https://guruhat.com")!)
                Link(T("Troubleshooting ›"), destination: helpURL)
            }
            .font(.caption).foregroundStyle(Theme.accent)
            Text(T("Windows is a trademark of Microsoft.\nGuruHat is not affiliated with or endorsed by Microsoft."))
                .multilineTextAlignment(.center).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
