import Foundation

/* App-level preferences. Same UserDefaults caveat as the rest of the suite:
   `swift run` and the bundled app use different defaults domains. */
enum AppPreferences {
    static let changed = Notification.Name("Keystone.PreferencesChanged")

    private static let remapEnabledKey = "pref.remapEnabled"
    private static let hideMenuBarIconKey = "pref.hideMenuBarIcon"
    private static let bindingsKey = "pref.keyBindings"
    private static let holdForCapsLockKey = "pref.holdForCapsLock"

    static var isMenuBarIconHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hideMenuBarIconKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: hideMenuBarIconKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /* The master switch over every key binding: off hands the whole
       keyboard back to stock macOS. On by default: remapping is the app's
       whole job, and onboarding has already told the user what enabling
       means. */
    static var isRemapEnabled: Bool {
        get { UserDefaults.standard.object(forKey: remapEnabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: remapEnabledKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    // MARK: Key bindings

    /* Each key (Caps Lock, ⌘ and ⌥ on either side) has one binding: what
       a press does, and how Keystone gets to know about the press.

       Two switching paths exist on purpose. The NATIVE path reroutes the
       key to a function key in the kernel and leaves the switching to the
       system's own "Select next source" shortcut, bound to that function
       key in Keyboard Settings — no permission, no process watching keys,
       and it keeps working where event taps go silent (secure input). It
       can only cycle, and the system has one such shortcut, so one key at
       a time gets it. The KEYSTONE path switches through the Text Input
       Source API from an event tap — any target, per key — at the price
       of the Input Monitoring permission. */
    enum SwitchAction: Equatable {
        /// Reroute in the kernel; the system shortcut does the switching.
        case native
        /// Cycle to the next enabled input source, like ⌃Space.
        case toggle
        /// Jump to one specific input source.
        case select(sourceID: String)

        /* Stored as a plain string: "native", "toggle", or the source ID
           prefixed. */
        var stored: String {
            switch self {
            case .native: "native"
            case .toggle: "toggle"
            case .select(let sourceID): "select:\(sourceID)"
            }
        }

        init?(stored: String) {
            if stored == "native" {
                self = .native
            } else if stored == "toggle" {
                self = .toggle
            } else if stored.hasPrefix("select:") {
                self = .select(sourceID: String(stored.dropFirst("select:".count)))
            } else {
                return nil
            }
        }
    }

    /* How a press reaches its action.

       REMAP reroutes the key to a function key in the kernel, for the
       native path: the system shortcut needs a real key to be bound to.

       PRESS reroutes the key to nothing at all (KeyRemap.noEventUsage) and
       Keystone watches the physical key below the remap, at the HID device
       layer: instant (the switch fires on key-down), invisible to every
       other process (no function key exists for a shortcut to collide
       with), but a modifier so rerouted stops being a modifier — its
       shortcuts are gone.

       RELEASE keeps the modifier untouched and switches only when it is
       pressed and released alone, at the cost of waiting for the release.
       Caps Lock has no modifier role to protect, so it is always pressed. */
    enum Trigger: Equatable {
        case remap(KeyRemap.FunctionKey)
        case press
        case release

        var stored: String {
            switch self {
            case .remap(let key): key.rawValue
            case .press: "press"
            case .release: "release"
            }
        }

        init?(stored: String) {
            if stored == "release" {
                self = .release
            } else if stored == "press" {
                self = .press
            } else if let key = KeyRemap.FunctionKey(rawValue: stored) {
                self = .remap(key)
            } else {
                return nil
            }
        }
    }

    struct KeyBinding: Equatable {
        var action: SwitchAction
        var trigger: Trigger

        /// The function key the kernel turns this key into (native path).
        var destination: KeyRemap.FunctionKey? {
            if case .remap(let key) = trigger { key } else { nil }
        }

        /// True when Keystone itself has to see the key — every path but
        /// the native one — and so needs Input Monitoring.
        var usesEventTap: Bool { action != .native }

        var stored: [String: String] {
            ["action": action.stored, "trigger": trigger.stored]
        }

        init(action: SwitchAction, trigger: Trigger) {
            self.action = action
            self.trigger = trigger
        }

        init?(stored: [String: String]) {
            guard let action = stored["action"].flatMap(SwitchAction.init(stored:)),
                let trigger = stored["trigger"].flatMap(Trigger.init(stored:))
            else { return nil }
            self.init(action: action, trigger: trigger)
        }
    }

    /// A fresh install: Caps Lock on the native path, F19 — the setup
    /// onboarding describes.
    static let defaultBindings: [KeyRemap.Key: KeyBinding] = [
        .capsLock: KeyBinding(action: .native, trigger: .remap(.f19))
    ]

    /// Keys without an entry are off.
    static var bindings: [KeyRemap.Key: KeyBinding] {
        get {
            guard
                let raw = UserDefaults.standard.dictionary(forKey: bindingsKey)
                    as? [String: [String: String]]
            else { return defaultBindings }
            return Self.parse(raw)
        }
        set {
            let raw = Dictionary(
                uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value.stored) })
            UserDefaults.standard.set(raw, forKey: bindingsKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    static func parse(_ raw: [String: [String: String]]) -> [KeyRemap.Key: KeyBinding] {
        var bindings: [KeyRemap.Key: KeyBinding] = [:]
        for (key, value) in raw {
            if let remapKey = KeyRemap.Key(rawValue: key), let binding = KeyBinding(stored: value) {
                bindings[remapKey] = binding
            }
        }
        return bindings
    }

    /// Sets one key's binding while keeping the whole set consistent: the
    /// native path belongs to one key at a time and is the only one with a
    /// function key, Caps Lock is never release-triggered, and no two keys
    /// share a function key. Returns the binding as actually stored.
    @discardableResult
    static func setBinding(_ binding: KeyBinding?, for key: KeyRemap.Key) -> KeyBinding? {
        var all = bindings
        let resolved = binding.map { Self.resolve($0, for: key, among: &all) }
        all[key] = resolved
        bindings = all
        return resolved
    }

    /* The consistency rules, on a value so they're testable. `all` loses
       any other key's native binding when `key` takes the native path. */
    static func resolve(
        _ binding: KeyBinding, for key: KeyRemap.Key, among all: inout [KeyRemap.Key: KeyBinding]
    ) -> KeyBinding {
        var binding = binding
        if binding.action == .native {
            for (other, existing) in all where other != key && existing.action == .native {
                all[other] = nil
            }
            let taken = Set(all.compactMap { $0.key == key ? nil : $0.value.destination })
            switch binding.trigger {
            case .remap(let destination) where !taken.contains(destination):
                break
            default:
                binding.trigger = .remap(freeFunctionKey(avoiding: taken))
            }
        } else {
            switch binding.trigger {
            case .release where key.isModifier: break
            default: binding.trigger = .press
            }
        }
        return binding
    }

    /// F19 when free — the conventional pick — otherwise the first spare
    /// in order. Never nil for a realistic set: eight keys, five bindings.
    static func freeFunctionKey(avoiding taken: Set<KeyRemap.FunctionKey>) -> KeyRemap.FunctionKey {
        if !taken.contains(.f19) { return .f19 }
        return KeyRemap.FunctionKey.allCases.first { !taken.contains($0) } ?? .f19
    }

    /// The function keys other keys occupy — what a destination picker
    /// for `key` leaves out.
    static func takenFunctionKeys(excluding key: KeyRemap.Key) -> Set<KeyRemap.FunctionKey> {
        Set(bindings.compactMap { $0.key == key ? nil : $0.value.destination })
    }

    /// Every rerouted key, for the HID mapping.
    static var mappings: [KeyRemap.Mapping] { mappingsFrom(bindings) }

    static func mappingsFrom(_ bindings: [KeyRemap.Key: KeyBinding]) -> [KeyRemap.Mapping] {
        bindings.compactMap { key, binding in
            switch binding.trigger {
            case .remap(let destination): KeyRemap.Mapping(key: key, destination: destination)
            case .press: KeyRemap.Mapping(key: key, destination: nil)
            case .release: nil
            }
        }
        .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    static var nativeKey: KeyRemap.Key? {
        bindings.first { $0.value.action == .native }?.key
    }

    /// True when any binding needs the Input Monitoring permission.
    static var needsInputMonitoring: Bool {
        bindings.values.contains { $0.usesEventTap }
    }

    // MARK: Migration

    /* Earlier versions kept the Caps Lock remap (on/off + destination) and
       the modifier lone-tap actions as separate preferences; 1.3.0 kept
       the taps as two side selections before that. Carry them all into
       key bindings once, then retire the old keys. Nothing changes for
       the user: Caps Lock stays on the native path with its destination,
       lone taps stay release-triggered.

       One wrinkle: the old Caps Lock switch didn't govern the taps, the
       new master switch governs everything. A user who had the remap off
       but taps on gets the same result as an off Caps Lock binding with
       the master on. */
    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: bindingsKey) == nil else { return }

        let destinationKey = "pref.destinationKey"
        let tapActionsKey = "pref.tapActions"
        let sideKeys = ["pref.commandSwitchKeys", "pref.optionSwitchKeys"]

        var tapActions = defaults.dictionary(forKey: tapActionsKey) as? [String: String] ?? [:]
        if defaults.object(forKey: tapActionsKey) == nil {
            tapActions = legacyTapActions(
                commandSides: defaults.string(forKey: sideKeys[0]),
                optionSides: defaults.string(forKey: sideKeys[1]))
        }
        let remapWasOn = defaults.object(forKey: remapEnabledKey) as? Bool ?? true
        let migrated = legacyBindings(
            capsLockRemapOn: remapWasOn || tapActions.isEmpty,
            destination: defaults.string(forKey: destinationKey)
                .flatMap(KeyRemap.FunctionKey.init(rawValue:)) ?? .f19,
            tapActions: tapActions)

        let raw = Dictionary(
            uniqueKeysWithValues: migrated.map { ($0.key.rawValue, $0.value.stored) })
        defaults.set(raw, forKey: bindingsKey)
        if !remapWasOn, !tapActions.isEmpty {
            defaults.set(true, forKey: remapEnabledKey)
        }
        for key in [destinationKey, tapActionsKey] + sideKeys {
            defaults.removeObject(forKey: key)
        }
    }

    /// 1.3.0's "left"/"right"/"both" side selections as toggle actions.
    static func legacyTapActions(commandSides: String?, optionSides: String?) -> [String: String] {
        var actions: [String: String] = [:]
        let sides = [
            (commandSides, KeyRemap.Key.leftCommand, KeyRemap.Key.rightCommand),
            (optionSides, KeyRemap.Key.leftOption, KeyRemap.Key.rightOption),
        ]
        for (selection, left, right) in sides {
            switch selection {
            case "left": actions[left.rawValue] = "toggle"
            case "right": actions[right.rawValue] = "toggle"
            case "both":
                actions[left.rawValue] = "toggle"
                actions[right.rawValue] = "toggle"
            default: break
            }
        }
        return actions
    }

    /// The pre-1.6 preferences expressed as key bindings.
    static func legacyBindings(
        capsLockRemapOn: Bool, destination: KeyRemap.FunctionKey, tapActions: [String: String]
    ) -> [KeyRemap.Key: KeyBinding] {
        var bindings: [KeyRemap.Key: KeyBinding] = [:]
        if capsLockRemapOn {
            bindings[.capsLock] = KeyBinding(action: .native, trigger: .remap(destination))
        }
        for (key, stored) in tapActions {
            if let remapKey = KeyRemap.Key(rawValue: key), remapKey.isModifier,
                let action = SwitchAction(stored: stored), action != .native
            {
                bindings[remapKey] = KeyBinding(action: action, trigger: .release)
            }
        }
        return bindings
    }

    // MARK: Hold for Caps Lock

    /* Off by default on purpose: distinguishing a tap from a hold costs
       the tap its key-down instancy (see HoldForCapsMonitor). */
    static var isHoldForCapsLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: holdForCapsLockKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: holdForCapsLockKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}
