import Foundation

/* The one system shortcut the native path leans on: "Select next source in
   Input menu", symbolic hotkey 61 in the com.apple.symbolichotkeys domain.
   System Settings writes it as `enabled` plus `parameters` [character,
   keycode, modifier flags]; an F key shows up with its virtual keycode and
   only the function-key flag set (measured 2026-09-18: Caps Lock → F19 is
   [65535, 80, 0x800000]). Reading it lets the settings pane tell whether
   the shortcut is already bound to the rerouted key, instead of asking the
   user to go and check. */
enum SystemHotkeys {
    static let domain = "com.apple.symbolichotkeys"
    static let hotkeysKey = "AppleSymbolicHotKeys"
    static let nextSourceHotkeyID = "61"

    /// NX_SECONDARYFNMASK — the flag every function key carries, which is
    /// not a modifier the user holds.
    static let functionKeyFlag: Int64 = 0x80_0000

    /// The keycode "Select next source in Input menu" is bound to, when it
    /// is enabled and bound to a bare key (no held modifiers). Nil when the
    /// shortcut is off, missing (the ⌃⌥Space default), or a chord.
    static func nextSourceKeyCode(in hotkeys: [String: Any]) -> Int64? {
        guard let entry = hotkeys[nextSourceHotkeyID] as? [String: Any] else { return nil }
        if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { return nil }
        guard
            let value = entry["value"] as? [String: Any],
            let parameters = value["parameters"] as? [Any], parameters.count == 3,
            let keyCode = (parameters[1] as? NSNumber)?.int64Value,
            let modifiers = (parameters[2] as? NSNumber)?.int64Value,
            modifiers & ~functionKeyFlag == 0
        else { return nil }
        return keyCode
    }

    /// The live value, re-read from cfprefsd each call so a change made in
    /// System Settings shows up as soon as the pane looks again.
    static func nextSourceKeyCode() -> Int64? {
        CFPreferencesAppSynchronize(domain as CFString)
        guard
            let hotkeys = CFPreferencesCopyAppValue(hotkeysKey as CFString, domain as CFString)
                as? [String: Any]
        else { return nil }
        return nextSourceKeyCode(in: hotkeys)
    }
}
