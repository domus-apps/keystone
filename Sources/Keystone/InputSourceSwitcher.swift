import Carbon

/* Selects keyboard input sources through the public Text Input Source
   APIs — either cycling to the next one (the way ⌃Space does) or jumping
   to a specific source a tap key is mapped to. No permissions involved. */
enum InputSourceSwitcher {
    /// One enabled, user-selectable source, as shown in the Input menu.
    struct Source: Equatable {
        let id: String
        let name: String
    }

    static func toggle() {
        let sources = selectableSources()
        guard sources.count > 1,
            let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        else { return }

        let currentID = property(of: current, kTISPropertyInputSourceID)
        let currentIndex = sources.firstIndex {
            property(of: $0, kTISPropertyInputSourceID) == currentID
        } ?? 0
        TISSelectInputSource(sources[(currentIndex + 1) % sources.count])
    }

    /// Selects the enabled source with `id`; a source that has since been
    /// disabled or removed is silently ignored (the mapping just does
    /// nothing until the user updates it).
    static func select(id: String) {
        guard
            let source = selectableSources().first(where: {
                property(of: $0, kTISPropertyInputSourceID) == id
            })
        else { return }
        TISSelectInputSource(source)
    }

    /// The sources the Settings pane offers for mapping.
    static func enabledSources() -> [Source] {
        selectableSources().compactMap { source in
            guard let id = property(of: source, kTISPropertyInputSourceID) else { return nil }
            return Source(
                id: id,
                name: property(of: source, kTISPropertyLocalizedName) ?? id)
        }
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

    private static func property(of source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
