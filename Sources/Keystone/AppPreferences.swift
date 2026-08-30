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
