import AppKit
import ApplicationServices
import SwiftUI

private func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}

private struct SwitchTarget: Identifiable {
    let id = UUID()
    let app: NSRunningApplication
    let window: AXUIElement?
    let title: String
    let detail: String
}

private final class SwitcherModel: ObservableObject {
    @Published var targets: [SwitchTarget] = []
    @Published var selected = 0
}

/// AX enumeration happens off the event-tap thread. Queued key presses and
/// Command release are retained while an app is responding to enumeration.
final class WindowSwitcher {
    private let model = SwitcherModel()
    private var panel: NSPanel?
    private var active = false
    private var loading = false
    private var commitWhenReady = false
    private var steps = 0
    private var generation = 0
    private var recency: [pid_t] = []
    private var consumedKeys = Set<Int64>()

    func recordActivation() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return }
        recency.removeAll { $0 == app.processIdentifier }
        recency.insert(app.processIdentifier, at: 0)
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, consumedKeys.remove(key) != nil { return true }
        if type == .flagsChanged {
            if active && !event.flags.contains(.maskCommand) { finish() }
            return false
        }
        guard type == .keyDown else { return false }
        if active && key == 53 {
            consumedKeys.insert(key)
            cancel()
            return true
        }
        let command = event.flags.contains(.maskCommand)
        let otherModifiers = !event.flags.intersection([.maskAlternate, .maskControl]).isEmpty
        guard command, !otherModifiers, key == 48 else { return false }
        consumedKeys.insert(key)
        let step = event.flags.contains(.maskShift) ? -1 : 1
        if !active { begin() }
        steps += step
        if !loading { updateSelection() }
        return true
    }

    private func begin() {
        active = true
        loading = true
        commitWhenReady = false
        steps = 0
        generation += 1
        let request = generation
        recordActivation()
        let order = recency
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated
        }.sorted {
            let left = order.firstIndex(of: $0.processIdentifier) ?? Int.max
            let right = order.firstIndex(of: $1.processIdentifier) ?? Int.max
            if left != right { return left < right }
            return ($0.localizedName ?? "") < ($1.localizedName ?? "")
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var targets: [SwitchTarget] = []
            for app in apps {
                let element = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(element, 0.15)
                let windows = axValue(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
                let focused = axValue(element, kAXFocusedWindowAttribute)
                var appTargets: [SwitchTarget] = []
                for window in windows {
                    AXUIElementSetMessagingTimeout(window, 0.15)
                    let role = axValue(window, kAXRoleAttribute) as? String
                    guard role == kAXWindowRole else { continue }
                    let title = axValue(window, kAXTitleAttribute) as? String ?? ""
                    let minimized = (axValue(window, kAXMinimizedAttribute) as? Bool) == true
                    let detail = [app.localizedName ?? "App", app.isHidden ? "Hidden" : nil,
                                  minimized ? "Minimized" : nil].compactMap { $0 }.joined(separator: " · ")
                    let target = SwitchTarget(app: app, window: window,
                                              title: title.isEmpty ? (app.localizedName ?? "Window") : title,
                                              detail: detail)
                    if let focused, CFEqual(focused, window) { appTargets.insert(target, at: 0) }
                    else { appTargets.append(target) }
                }
                if appTargets.isEmpty {
                    appTargets.append(SwitchTarget(app: app, window: nil, title: app.localizedName ?? "App",
                                                   detail: app.isHidden ? "Hidden app" : "App"))
                }
                targets.append(contentsOf: appTargets)
            }
            DispatchQueue.main.async {
                guard let self, self.active, self.generation == request else { return }
                self.loading = false
                self.model.targets = targets
                guard !targets.isEmpty else { self.cancel(); return }
                self.updateSelection()
                if self.commitWhenReady { self.finish() }
                else { self.showPanel() }
            }
        }
    }

    private func updateSelection() {
        model.selected = SwitcherNavigation.index(steps: steps, count: model.targets.count)
    }

    private func showPanel() {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                                backing: .buffered, defer: false)
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: SwitcherView(model: model))
            self.panel = panel
        }
        panel?.center()
        panel?.orderFrontRegardless()
    }

    private func finish() {
        guard active else { return }
        if loading { commitWhenReady = true; return }
        guard model.targets.indices.contains(model.selected) else { cancel(); return }
        let target = model.targets[model.selected]
        cancel()
        // Restore only the selected window. Hidden apps stay in the list even
        // when AX cannot enumerate their windows, using an app-level fallback.
        DispatchQueue.main.async {
            guard !target.app.isTerminated else { return }
            target.app.unhide()
            target.app.activate(options: [.activateIgnoringOtherApps])
            if let window = target.window {
                DispatchQueue.global(qos: .userInitiated).async {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                }
            } else if let url = target.app.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
        }
    }

    func cancel() {
        active = false
        loading = false
        commitWhenReady = false
        generation += 1
        panel?.orderOut(nil)
        model.targets = []
    }
}

private struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Windows & Apps").font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(model.targets.enumerated()), id: \.element.id) { index, target in
                            HStack(spacing: 12) {
                                Image(nsImage: target.app.icon ?? NSImage())
                                    .resizable().frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(target.title).lineLimit(1)
                                    Text(target.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(index == model.selected ? Color.accentColor.opacity(0.22) : Color.clear)
                            .cornerRadius(8)
                            .id(index)
                        }
                    }
                }
                .onChange(of: model.selected) { index in proxy.scrollTo(index) }
                .onAppear { proxy.scrollTo(model.selected) }
            }
            Text("Tab: next   Release ⌘: open")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}
