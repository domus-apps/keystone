import Foundation

/* App-level preferences. Same UserDefaults caveat as the rest of the suite:
   `swift run` and the bundled app use different defaults domains. */
enum AppPreferences {
    static let changed = Notification.Name("Keystone.PreferencesChanged")

    private static let remapEnabledKey = "pref.remapEnabled"
    private static let destinationKeyKey = "pref.destinationKey"
    private static let hideMenuBarIconKey = "pref.hideMenuBarIcon"

    static var isMenuBarIconHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hideMenuBarIconKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: hideMenuBarIconKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /* On by default: remapping is the app's whole job, and onboarding has
       already told the user what enabling means. */
    static var isRemapEnabled: Bool {
        get { UserDefaults.standard.object(forKey: remapEnabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: remapEnabledKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /* Modifier-tap input switching: each ⌘/⌥ key can, when pressed and
       released alone, either cycle the input source or jump to a specific
       one (combos always keep working — a full remap would cost the key
       its modifier role, which is too much to take from a Mac). All off
       by default: the watcher needs an Input Monitoring grant, so the
       feature is strictly opt-in. */
    enum TapKey: String, CaseIterable {
        case leftCommand, rightCommand, leftOption, rightOption

        var title: String {
            switch self {
            case .leftCommand: "Left ⌘"
            case .rightCommand: "Right ⌘"
            case .leftOption: "Left ⌥"
            case .rightOption: "Right ⌥"
            }
        }
    }

    enum TapAction: Equatable {
        /// Cycle to the next enabled input source, like ⌃Space.
        case toggle
        /// Jump to one specific input source.
        case select(sourceID: String)

        /* Stored as a plain string: "toggle", or the source ID prefixed. */
        var stored: String {
            switch self {
            case .toggle: "toggle"
            case .select(let sourceID): "select:\(sourceID)"
            }
        }

        init?(stored: String) {
            if stored == "toggle" {
                self = .toggle
            } else if stored.hasPrefix("select:") {
                self = .select(sourceID: String(stored.dropFirst("select:".count)))
            } else {
                return nil
            }
        }
    }

    private static let tapActionsKey = "pref.tapActions"

    /// Keys without an entry are off.
    static var tapActions: [TapKey: TapAction] {
        get {
            let raw =
                UserDefaults.standard.dictionary(forKey: tapActionsKey) as? [String: String]
                ?? [:]
            var actions: [TapKey: TapAction] = [:]
            for (key, value) in raw {
                if let tapKey = TapKey(rawValue: key), let action = TapAction(stored: value) {
                    actions[tapKey] = action
                }
            }
            return actions
        }
        set {
            let raw = Dictionary(
                uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value.stored) })
            UserDefaults.standard.set(raw, forKey: tapActionsKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    static func setTapAction(_ action: TapAction?, for key: TapKey) {
        var actions = tapActions
        actions[key] = action
        tapActions = actions
    }

    /* 1.3.0 stored the tap feature as two side selections; carry them over
       as toggle actions once, then retire the old keys. */
    static func migrateTapPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: tapActionsKey) == nil else { return }

        var actions: [TapKey: TapAction] = [:]
        let sides = [
            ("pref.commandSwitchKeys", TapKey.leftCommand, TapKey.rightCommand),
            ("pref.optionSwitchKeys", TapKey.leftOption, TapKey.rightOption),
        ]
        for (oldKey, left, right) in sides {
            switch defaults.string(forKey: oldKey) {
            case "left": actions[left] = .toggle
            case "right": actions[right] = .toggle
            case "both":
                actions[left] = .toggle
                actions[right] = .toggle
            default: break
            }
            defaults.removeObject(forKey: oldKey)
        }
        if !actions.isEmpty {
            tapActions = actions
        }
    }

    /* Falls back to the conventional F19 for unset or unrecognized values. */
    static var destination: KeyRemap.FunctionKey {
        get {
            UserDefaults.standard.string(forKey: destinationKeyKey)
                .flatMap(KeyRemap.FunctionKey.init(rawValue:)) ?? .f19
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: destinationKeyKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}
