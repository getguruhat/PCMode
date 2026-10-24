# PC Mode

A macOS menu-bar utility for Finder actions and switching between individual
windows.

## Download

[Download PC Mode for macOS](../../releases/latest/download/PCMode-Installer.dmg)

The installer is distributed through this GitHub repository. Open the link above
to download `PCMode-Installer.dmg`, then open the downloaded disk image and drag
**PC Mode.app** to your Applications folder. If GitHub does not have a published
release yet, use the [Releases](../../releases) page to download the latest
available installer.

- **Finder Trash:** while Finder is frontmost, press the selected media key to
  move selected items to Trash. Rewind (F7) is the default; F7–F12 are
  selectable (Rewind, Play/Pause, Forward, Mute, Volume Down, and Volume Up).
- **Finder cut/move:** in Finder, Cmd+X copies selected files. The next Cmd+V in
  a destination folder moves those copied files; copying again, changing the
  clipboard, or leaving Finder cancels the pending move.
- **Windows & Apps:** Cmd+Tab switches between individual windows, including
  hidden and minimized windows. Hold Cmd while pressing Tab to select, release
  Cmd to open the selection, use Shift+Tab to move backward, or Escape to cancel.
  Disable this feature to restore macOS’s standard Cmd+Tab behavior.
- **CPU and RAM in the switcher:** each app shows its CPU and memory use,
  including its helper processes (browser tabs, Electron helpers), measured the
  same way as Activity Monitor. CPU turns orange at 40% and red at 90%. RAM is
  only highlighted for apps over 1 GB when macOS reports memory pressure, since
  a full-looking RAM number alone is normal on a Mac.

Click the PC Mode menu-bar icon to open Settings and About. Changes to the
available feature settings save immediately.

PC Mode attempts to register itself to launch at login. For reliable startup, move
PC Mode.app to the Applications folder before opening it; macOS may ask you to
approve it in **System Settings → General → Login Items**.

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

Enable PC Mode in **System Settings → Privacy & Security → Accessibility** and
**Input Monitoring**. The Settings **Manage** button opens the system permission
requests, and the status indicator reports when all required permissions are ready.

Local builds are ad-hoc signed. Rebuilding can require granting permissions again.
Quit other keyboard remappers before use to avoid conflicting shortcuts.

The installer build creates `PCMode.app` and `PCMode-Installer.dmg` in the project
folder. The included tests cover the shortcut press gate, Finder move state, key
mappings, switcher navigation logic, and CPU/RAM formatting and thresholds.
