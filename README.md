# PC Mode

A macOS menu-bar utility with three independently configurable shortcuts:

## Download

[Download PC Mode for macOS](../../releases/latest/download/PCMode-Installer.dmg)

The installer is distributed through this GitHub repository. Open the link above
to download `PCMode-Installer.dmg`, then open the downloaded disk image and drag
**PC Mode.app** to your Applications folder. If GitHub does not have a published
release yet, use the [Releases](../../releases) page to download the latest
available installer.

- **Finder Trash:** map a top-row key to Command+Delete. Rewind / Previous / F7
  is the default; playback, volume, brightness, F1–F12 and Eject are selectable.
- **Finder cut/move:** Cmd+X copies selected files and arms one Cmd+V move into
  the destination folder. Copying again or leaving Finder cancels the move.
- **Windows & Apps:** hold Cmd and press Tab to select a window or app, including
  hidden apps and minimized windows. Release Cmd to activate and restore the
  selection; Shift+Tab reverses and Escape cancels. This feature works globally.
  Turn it off to restore macOS's standard Cmd+Tab.

Open **PC Mode → Settings & About…** for the Settings and About window. Preferences
save immediately. The menu contains Settings & About and Quit.

PC Mode registers itself as a macOS Login Item on first launch so its shortcuts are
ready after every sign-in. This can be turned off in Settings. For reliable startup,
install PC Mode.app in the Applications folder before opening it for the first time.

The switcher uses Accessibility to enumerate windows, with an app entry when an
app exposes no windows. It unhides the selected app, restores the selected
minimized window and raises it. Apps may restrict which windows they expose.
Window enumeration runs in the background with bounded Accessibility calls.

## Build and run

Requires macOS 13+ and Swift Command Line Tools.

```sh
./test.sh
./build-app.sh
open ./PCMode.app --args --settings
```

Enable this app in **System Settings → Privacy & Security → Accessibility** and
**Input Monitoring**, then restart. The Settings permission button requests the
required access; the adjacent status indicates whether it is ready.

Local builds are ad-hoc signed, so rebuilding can invalidate existing grants.
If needed, remove and re-add this exact app in both permission lists. A stable
Apple signing identity is needed for production updates that preserve trust.
Quit other keyboard remappers such as WinMode or Finder Move Here before use.

F3–F6 may require Fn on newer keyboards to send function-key events. HID is
observed rather than seized, so certain keyboards may also perform their native
media action. Trash delivery uses Quartz events addressed specifically to Finder.
Held keys and overlapping input paths are suppressed by a shared press gate.

The app no longer includes diagnostic menus, synthetic input commands, test-file
creation, per-key file logging, or the System Events fallback. Source-level
regression tests remain in Tests and do not manipulate real files or windows.
