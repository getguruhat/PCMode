/// macOS virtual keys and media codes (ev_keymap.h / IOHIDUsageTables.h).
enum DeleteKey: String, CaseIterable, Identifiable {
    case brightnessDown, brightnessUp, f3, f4, f5, f6
    case rewind, playPause, forward, mute, volumeDown, volumeUp, eject

    /// The media/function keys shown in the user-facing Delete key picker.
    static let menuCases: [DeleteKey] = [.rewind, .playPause, .forward, .mute, .volumeDown, .volumeUp]

    var id: String { rawValue }
    var title: String {
        switch self {
        case .brightnessDown: return "Brightness down / F1"
        case .brightnessUp: return "Brightness up / F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "Keyboard brightness down / F5"
        case .f6: return "Keyboard brightness up / F6"
        case .rewind: return "⏮  F7"
        case .playPause: return "⏯  F8"
        case .forward: return "⏭  F9"
        case .mute: return "🔇  F10"
        case .volumeDown: return "🔉  F11"
        case .volumeUp: return "🔊  F12"
        case .eject: return "Eject"
        }
    }
    var symbolName: String {
        switch self {
        case .rewind: return "backward.fill"
        case .playPause: return "playpause.fill"
        case .forward: return "forward.fill"
        case .mute: return "speaker.slash.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .volumeUp: return "speaker.wave.3.fill"
        default: return "function"
        }
    }
    var menuTitle: String {
        switch self {
        case .rewind: return "F7"
        case .playPause: return "F8"
        case .forward: return "F9"
        case .mute: return "F10"
        case .volumeDown: return "F11"
        case .volumeUp: return "F12"
        default: return title
        }
    }
    var keyCode: Int64? {
        switch self {
        case .brightnessDown: return 122
        case .brightnessUp: return 120
        case .f3: return 99
        case .f4: return 118
        case .f5: return 96
        case .f6: return 97
        case .rewind: return 98
        case .playPause: return 100
        case .forward: return 101
        case .mute: return 109
        case .volumeDown: return 103
        case .volumeUp: return 111
        case .eject: return nil
        }
    }
    var mediaCodes: Set<UInt32> {
        switch self {
        case .brightnessDown: return [3]
        case .brightnessUp: return [2]
        case .f3, .f4: return []
        case .f5: return [22]
        case .f6: return [21]
        case .rewind: return [18, 20]
        case .playPause: return [16]
        case .forward: return [17, 19]
        case .mute: return [7]
        case .volumeDown: return [1]
        case .volumeUp: return [0]
        case .eject: return [14]
        }
    }
    var consumerUsages: Set<UInt32> {
        switch self {
        case .brightnessDown: return [0x70]
        case .brightnessUp: return [0x6f]
        case .rewind: return [0xb4, 0xb6]
        case .playPause: return [0xb0, 0xb1, 0xcd]
        case .forward: return [0xb3, 0xb5]
        case .mute: return [0xe2]
        case .volumeDown: return [0xea]
        case .volumeUp: return [0xe9]
        case .eject: return [0xb8]
        case .f3, .f4, .f5, .f6: return []
        }
    }
}
