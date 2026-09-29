import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hid

private func finder() -> NSRunningApplication? {
    guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.apple.finder" else { return nil }
    return app
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var monitor: Any?
    private var hid: IOHIDManager?
    private var timer: Timer?
    private var gate = PressGate()
    private var cut = CutState()
    private var consumedPaste = false
    private var activationObserver: NSObjectProtocol?
    private let injectedEventTag: Int64 = 0x77696e32
    private var item: NSStatusItem!
    private let settings = WinSettings()
    private let settingsWindow = SettingsWindowController()
    private var settingsRevision = 0
    private let switcher = WindowSwitcher()
    private var isBackgroundLaunch: Bool { CommandLine.arguments.contains("--background") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LaunchServices normally enforces this; also protect against direct binary launches.
        if NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }) { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let iconURL = Bundle.main.url(forResource: "HatMenu", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: 20, height: 20)
            icon.isTemplate = false
            item.button?.image = icon
            item.button?.imagePosition = .imageOnly
            item.button?.toolTip = "PC Mode"
        } else {
            item.button?.title = "PC"
        }
        item.isVisible = settings.menuBarIconEnabled
        item.button?.target = self
        item.button?.action = #selector(showSettings)
        item.button?.sendAction(on: [.leftMouseUp])
        settings.onChange = { [weak self] in
            guard let self else { return }
            self.settingsRevision += 1
            self.gate = PressGate()
            self.cut.cancel()
            self.switcher.cancel()
            self.item?.isVisible = self.settings.menuBarIconEnabled
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            if finder() == nil { self?.cut.cancel() }
            self?.switcher.recordActivation()
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        guard !isBackgroundLaunch else { return false }
        showSettings()
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func showSettings() {
        settingsWindow.show(settings: settings) { [weak self] in self?.requestPermissions() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func requestPermissions() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        _ = CGRequestListenEventAccess()
        _ = CGRequestPostEventAccess()
        refresh()
    }
    private func refresh() {
        let ax = AXIsProcessTrusted(), listen = CGPreflightListenEventAccess(), post = CGPreflightPostEventAccess()
        settings.permissionMessage = ax && listen && post
            ? "Ready"
            : "Enable Device Control and Data Access, then restart."
        guard ax && listen && post else { switcher.cancel(); return }
        if tap == nil { installTap() }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        if monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
                self?.media(event, path: "NSEvent")
            }
        }
        if hid == nil { installHID() }
    }
    private func installTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                               eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().event(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { settings.permissionMessage = "Enable permissions, then restart PC Mode."; return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    private func event(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // These notifications must be handled regardless of the frontmost app.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            switcher.cancel()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == injectedEventTag {
            return Unmanaged.passUnretained(event)
        }
        if settings.switcherEnabled, switcher.handle(type: type, event: event) { return nil }
        if event.getIntegerValueField(.keyboardEventKeycode) == 9, consumedPaste {
            if type == .keyUp { consumedPaste = false }
            if type == .keyDown || type == .keyUp { return nil }
        }
        if type == .keyDown, handleCutKey(event) { return nil }
        if type.rawValue == 14, let ns = NSEvent(cgEvent: event), media(ns, path: "CGEvent media") {
            return finder() == nil ? Unmanaged.passUnretained(event) : nil
        }
        if settings.deleteEnabled, (type == .keyDown || type == .keyUp),
           event.getIntegerValueField(.keyboardEventKeycode) == settings.deleteKey.keyCode {
            let down = type == .keyDown
            let modified = !event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
            receive(path: "CGEvent function key", down: down,
                    repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, eligible: !modified)
            if finder() != nil && !modified { return nil }
        }
        return Unmanaged.passUnretained(event)
    }
    private func handleCutKey(_ event: CGEvent) -> Bool {
        guard settings.cutEnabled else { cut.cancel(); return false }
        guard let target = finder() else { cut.cancel(); return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        guard modifiers == .maskCommand else { return false }
        if key == 8 { cut.cancel(); return false } // Explicit Copy replaces a pending cut.
        if key == 7 {
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }
            let generation = cut.begin(changeCount: NSPasteboard.general.changeCount)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.cut.generation == generation else { return }
                guard self.postFinderKey(8, flags: .maskCommand, to: target.processIdentifier) else {
                    self.cut.cancel(); return
                }
                self.waitForCopy(generation: generation, remaining: 20)
            }
            return true
        }
        if key == 9 {
            if cut.pending { consumedPaste = true; return true } // Do not paste the old clipboard while Copy is in flight.
            guard cut.consume(changeCount: NSPasteboard.general.changeCount) else { return false }
            consumedPaste = true
            let revision = settingsRevision
            DispatchQueue.main.async { [weak self] in
                guard let self, self.settings.cutEnabled, self.settingsRevision == revision else { return }
                _ = self.postFinderKey(9, flags: [.maskCommand, .maskAlternate], to: target.processIdentifier)
            }
            return true
        }
        return false
    }
    private func waitForCopy(generation: Int, remaining: Int) {
        guard cut.generation == generation, cut.pending else { return }
        guard finder() != nil else { cut.cancel(); return }
        let board = NSPasteboard.general
        if board.changeCount != cut.originalChangeCount {
            let hasFiles = board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            cut.finish(changeCount: board.changeCount, hasFiles: hasFiles)
        } else if remaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.waitForCopy(generation: generation, remaining: remaining - 1)
            }
        } else { cut.cancel() }
    }
    private func postFinderKey(_ key: CGKeyCode, flags: CGEventFlags, to pid: pid_t) -> Bool {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess(), finder()?.processIdentifier == pid else { return false }
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: injectedEventTag)
            event.postToPid(pid)
        }
        return true
    }
    @discardableResult private func media(_ event: NSEvent, path: String) -> Bool {
        guard settings.deleteEnabled, event.subtype.rawValue == 8 else { return false }
        let data = UInt32(truncatingIfNeeded: event.data1)
        let key = (data >> 16) & 0xffff, state = (data >> 8) & 0xff
        guard settings.deleteKey.mediaCodes.contains(key), state == 0x0a || state == 0x0b else { return false }
        let modified = !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        receive(path: path, down: state == 0x0a, repeating: (data & 1) != 0, eligible: !modified)
        return !modified
    }
    private func installHID() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        // Match keyboard collections too: consumer elements can live on a composite keyboard.
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDDeviceUsagePageKey: 0x0c],
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x06]
        ] as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let element = IOHIDValueGetElement(value)
            let usage = IOHIDElementGetUsage(element)
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            guard IOHIDElementGetUsagePage(element) == 0x0c, app.settings.deleteEnabled,
                  app.settings.deleteKey.consumerUsages.contains(usage) else { return }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let modified = !flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
            app.receive(path: "HID \(String(usage, radix: 16))", down: IOHIDValueGetIntegerValue(value) != 0,
                        repeating: false, eligible: !modified)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
            return
        }
        hid = manager
    }
    private func receive(path: String, down: Bool, repeating: Bool, eligible: Bool = true) {
        let accepted = gate.receive(path: path, down: down, repeating: repeating, now: ProcessInfo.processInfo.systemUptime)
        guard settings.deleteEnabled, accepted, eligible, let target = finder() else { return }
        let revision = settingsRevision
        // Leave the event-tap callback immediately, then recheck focus before posting.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.settings.deleteEnabled, self.settingsRevision == revision,
                  finder()?.processIdentifier == target.processIdentifier else { return }
            _ = self.postFinderKey(51, flags: .maskCommand, to: target.processIdentifier)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        switcher.cancel()
        timer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let hid {
            IOHIDManagerUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(hid, 0)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
