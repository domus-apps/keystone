import Carbon

/* Cycles to the next enabled keyboard input source, the way ⌃Space does —
   used by the tap-alone Right Command mode, which can't lean on the
   System Settings shortcut the spare-key remaps use. Public Text Input
   Source APIs only; no permissions involved. */
enum InputSourceSwitcher {
    static func toggle() {
        let sources = selectableSources()
        guard sources.count > 1,
            let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        else { return }

        let currentID = sourceID(of: current)
        let currentIndex = sources.firstIndex { sourceID(of: $0) == currentID } ?? 0
        let next = sources[(currentIndex + 1) % sources.count]
        TISSelectInputSource(next)
    }

    /* What the Input menu cycles through: enabled, user-selectable layouts
       and input modes (Korean 2-Set is a mode of the Korean input method —
       the parent method itself is not in the rotation). */
    private static func selectableSources() -> [TISInputSource] {
        let filter =
            [
                kTISPropertyInputSourceCategory as String:
                    kTISCategoryKeyboardInputSource as Any,
                kTISPropertyInputSourceIsSelectCapable as String: true,
                kTISPropertyInputSourceIsEnabled as String: true,
            ] as CFDictionary
        let list =
            TISCreateInputSourceList(filter, false)?.takeRetainedValue()
            as? [TISInputSource] ?? []
        return list.filter { source in
            let type = property(of: source, kTISPropertyInputSourceType)
            return type == (kTISTypeKeyboardLayout as String)
                || type == (kTISTypeKeyboardInputMode as String)
        }
    }

    private static func sourceID(of source: TISInputSource) -> String? {
        property(of: source, kTISPropertyInputSourceID)
    }

    private static func property(of source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
