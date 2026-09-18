import Foundation
import Testing

@testable import Keystone

@Test func capsLockUsageIsTheHIDKeyboardPage() {
    #expect(KeyRemap.capsLockUsage == 0x7_0000_0039)
    #expect(KeyRemap.Key.capsLock.usage == 0x7_0000_0039)
}

@Test func modifierUsagesMatchTheHIDKeyboardPage() {
    #expect(KeyRemap.Key.leftCommand.usage == 0x7_0000_00E3)
    #expect(KeyRemap.Key.rightCommand.usage == 0x7_0000_00E7)
    #expect(KeyRemap.Key.leftOption.usage == 0x7_0000_00E2)
    #expect(KeyRemap.Key.rightOption.usage == 0x7_0000_00E6)
    #expect(KeyRemap.Key.allCases.filter(\.isModifier).count == 4)
    #expect(!KeyRemap.Key.capsLock.isModifier)
}

@Test func functionKeyUsagesAreContiguousFromF13() {
    #expect(KeyRemap.FunctionKey.f13.usage == 0x7_0000_0068)
    #expect(KeyRemap.FunctionKey.f19.usage == 0x7_0000_006E)
    #expect(KeyRemap.FunctionKey.f20.usage == 0x7_0000_006F)
}

@Test func mappingArgumentIsValidJSONWithOnePairPerKey() throws {
    let argument = KeyRemap.mappingArgument([
        KeyRemap.Mapping(key: .capsLock, destination: .f19),
        KeyRemap.Mapping(key: .rightCommand, destination: nil),
    ])
    let object = try JSONSerialization.jsonObject(with: Data(argument.utf8)) as? [String: Any]
    let mappings = try #require(object?["UserKeyMapping"] as? [[String: Any]])
    #expect(mappings.count == 2)
    #expect(mappings[0]["HIDKeyboardModifierMappingSrc"] as? UInt64 == KeyRemap.capsLockUsage)
    #expect(
        mappings[0]["HIDKeyboardModifierMappingDst"] as? UInt64
            == KeyRemap.FunctionKey.f19.usage)
    #expect(
        mappings[1]["HIDKeyboardModifierMappingSrc"] as? UInt64
            == KeyRemap.Key.rightCommand.usage)
    /* Rerouted to nothing: the keyboard page's "no event" usage. */
    #expect(mappings[1]["HIDKeyboardModifierMappingDst"] as? UInt64 == 0x7_0000_0000)
    #expect(KeyRemap.noEventUsage == 0x7_0000_0000)
}

@Test func emptyMappingArgumentEqualsTheClearArgument() {
    #expect(KeyRemap.mappingArgument([]) == KeyRemap.clearArgument)
}

@Test func switchActionsRoundTripThroughStorage() {
    #expect(AppPreferences.SwitchAction(stored: "native") == .native)
    #expect(AppPreferences.SwitchAction(stored: "toggle") == .toggle)
    #expect(
        AppPreferences.SwitchAction(stored: "select:com.apple.keylayout.ABC")
            == .select(sourceID: "com.apple.keylayout.ABC"))
    #expect(AppPreferences.SwitchAction(stored: "nonsense") == nil)
    #expect(AppPreferences.SwitchAction.native.stored == "native")
    #expect(AppPreferences.SwitchAction.toggle.stored == "toggle")
    #expect(
        AppPreferences.SwitchAction.select(sourceID: "a.b").stored == "select:a.b")
}

@Test func keyBindingsRoundTripThroughStorage() {
    let binding = AppPreferences.KeyBinding(action: .select(sourceID: "x"), trigger: .press)
    #expect(binding.stored == ["action": "select:x", "trigger": "press"])
    #expect(AppPreferences.KeyBinding(stored: binding.stored) == binding)
    let native = AppPreferences.KeyBinding(action: .native, trigger: .remap(.f14))
    #expect(native.stored == ["action": "native", "trigger": "f14"])
    #expect(AppPreferences.KeyBinding(stored: native.stored) == native)
    #expect(native.destination == .f14)
    let release = AppPreferences.KeyBinding(action: .toggle, trigger: .release)
    #expect(AppPreferences.KeyBinding(stored: ["action": "toggle", "trigger": "release"]) == release)
    #expect(release.destination == nil)
    #expect(AppPreferences.KeyBinding(stored: ["action": "toggle", "trigger": "f99"]) == nil)
    #expect(AppPreferences.KeyBinding(stored: ["action": "toggle"]) == nil)
    let parsed = AppPreferences.parse([
        "capsLock": ["action": "native", "trigger": "f19"],
        "bogus": ["action": "toggle", "trigger": "release"],
    ])
    #expect(parsed == [.capsLock: AppPreferences.KeyBinding(action: .native, trigger: .remap(.f19))])
}

@Test func nativePathMovesToTheKeyThatTakesIt() {
    var all: [KeyRemap.Key: AppPreferences.KeyBinding] = [
        .capsLock: .init(action: .native, trigger: .remap(.f19))
    ]
    let resolved = AppPreferences.resolve(
        .init(action: .native, trigger: .release), for: .rightCommand, among: &all)
    #expect(all[.capsLock] == nil)
    /* Native needs a function key, and F19 is free again once Caps Lock
       let go of it. */
    #expect(resolved == .init(action: .native, trigger: .remap(.f19)))
}

@Test func keystonePathNeverCarriesAFunctionKey() {
    var all: [KeyRemap.Key: AppPreferences.KeyBinding] = [
        .capsLock: .init(action: .native, trigger: .remap(.f19))
    ]
    /* A function key on a Keystone-path binding (a stale value, say) is
       normalized to the press trigger: the key is rerouted to nothing. */
    let stale = AppPreferences.resolve(
        .init(action: .toggle, trigger: .remap(.f19)), for: .rightCommand, among: &all)
    #expect(stale.trigger == .press)
    /* Caps Lock can't be release-triggered. */
    let caps = AppPreferences.resolve(
        .init(action: .toggle, trigger: .release), for: .capsLock, among: &all)
    #expect(caps.trigger == .press)
    /* A modifier switched by Keystone may stay a modifier. */
    let release = AppPreferences.resolve(
        .init(action: .toggle, trigger: .release), for: .leftOption, among: &all)
    #expect(release.trigger == .release)
    #expect(all.count == 1)
}

@Test func mappingsCoverEveryReroutedKeyAndSkipReleaseKeys() {
    let mappings = AppPreferences.mappingsFrom([
        .capsLock: .init(action: .native, trigger: .remap(.f19)),
        .leftCommand: .init(action: .toggle, trigger: .press),
        .rightCommand: .init(action: .toggle, trigger: .release),
    ])
    #expect(mappings == [
        KeyRemap.Mapping(key: .capsLock, destination: .f19),
        KeyRemap.Mapping(key: .leftCommand, destination: nil),
    ])
}

@Test func legacyPreferencesBecomeEquivalentBindings() {
    let bindings = AppPreferences.legacyBindings(
        capsLockRemapOn: true, destination: .f17,
        tapActions: ["leftCommand": "toggle", "rightOption": "select:ko", "capsLock": "toggle"])
    #expect(bindings[.capsLock] == .init(action: .native, trigger: .remap(.f17)))
    #expect(bindings[.leftCommand] == .init(action: .toggle, trigger: .release))
    #expect(bindings[.rightOption] == .init(action: .select(sourceID: "ko"), trigger: .release))
    #expect(bindings.count == 3)
    #expect(AppPreferences.legacyBindings(capsLockRemapOn: false, destination: .f19, tapActions: [:]).isEmpty)
}

@Test func legacySideSelectionsBecomeToggleTaps() {
    let actions = AppPreferences.legacyTapActions(commandSides: "both", optionSides: "right")
    #expect(actions == ["leftCommand": "toggle", "rightCommand": "toggle", "rightOption": "toggle"])
    #expect(AppPreferences.legacyTapActions(commandSides: nil, optionSides: nil).isEmpty)
}

@Test func migrationWritesBindingsOnceAndRetiresOldKeys() throws {
    let suite = "KeystoneTests.migration.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "pref.remapEnabled")
    defaults.set("f18", forKey: "pref.destinationKey")
    defaults.set(["leftCommand": "toggle"], forKey: "pref.tapActions")

    AppPreferences.migrateIfNeeded(defaults: defaults)

    let raw = defaults.dictionary(forKey: "pref.keyBindings") as? [String: [String: String]]
    #expect(raw == ["leftCommand": ["action": "toggle", "trigger": "release"]])
    /* Remap off + taps on: the taps used to run regardless, so the master
       switch comes on and Caps Lock alone stays off. */
    #expect(defaults.bool(forKey: "pref.remapEnabled") == true)
    #expect(defaults.object(forKey: "pref.destinationKey") == nil)
    #expect(defaults.object(forKey: "pref.tapActions") == nil)

    /* Second run: nothing to do. */
    defaults.set("f13", forKey: "pref.destinationKey")
    AppPreferences.migrateIfNeeded(defaults: defaults)
    #expect(defaults.string(forKey: "pref.destinationKey") == "f13")
}

@Test func freshInstallMigratesToTheOnboardingDefault() throws {
    let suite = "KeystoneTests.fresh.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    AppPreferences.migrateIfNeeded(defaults: defaults)
    let raw = defaults.dictionary(forKey: "pref.keyBindings") as? [String: [String: String]]
    #expect(raw == ["capsLock": ["action": "native", "trigger": "f19"]])
    #expect(defaults.object(forKey: "pref.remapEnabled") == nil)
}

@Test func clearArgumentIsAnEmptyMappingList() throws {
    let object =
        try JSONSerialization.jsonObject(with: Data(KeyRemap.clearArgument.utf8))
        as? [String: Any]
    let mappings = try #require(object?["UserKeyMapping"] as? [Any])
    #expect(mappings.isEmpty)
}

@Test func keyboardMatchingTargetsTheKeyboardUsagePair() throws {
    let object =
        try JSONSerialization.jsonObject(with: Data(KeyRemap.keyboardMatchingArgument.utf8))
        as? [String: Int]
    #expect(object?["PrimaryUsagePage"] == 1)
    #expect(object?["PrimaryUsage"] == 6)
}

@Test func titlesReadAsFunctionKeys() {
    #expect(KeyRemap.FunctionKey.f19.title == "F19")
    #expect(KeyRemap.FunctionKey.allCases.count == 8)
}

@Test func functionKeyKeycodesMatchTheVirtualKeyTable() {
    #expect(KeyRemap.FunctionKey.f13.keyCode == 105)
    #expect(KeyRemap.FunctionKey.f17.keyCode == 64)
    #expect(KeyRemap.FunctionKey.f19.keyCode == 80)
    #expect(KeyRemap.FunctionKey.f20.keyCode == 90)
}

private func hotkeys(enabled: Bool = true, keyCode: Int, modifiers: Int = 0x80_0000) -> [String: Any] {
    [
        "61": [
            "enabled": enabled,
            "value": ["type": "standard", "parameters": [65535, keyCode, modifiers]],
        ] as [String: Any]
    ]
}

@Test func nextSourceShortcutReadsABareFunctionKey() {
    #expect(SystemHotkeys.nextSourceKeyCode(in: hotkeys(keyCode: 80)) == 80)
    #expect(SystemHotkeys.nextSourceKeyCode(in: hotkeys(keyCode: 80)) == KeyRemap.FunctionKey.f19.keyCode)
}

@Test func nextSourceShortcutIgnoresDisabledChordedOrMissingBindings() {
    #expect(SystemHotkeys.nextSourceKeyCode(in: hotkeys(enabled: false, keyCode: 80)) == nil)
    /* ⌃⌥Space, the stock binding: a chord, not a rerouted key. */
    #expect(SystemHotkeys.nextSourceKeyCode(in: hotkeys(keyCode: 49, modifiers: 0xC0000)) == nil)
    #expect(SystemHotkeys.nextSourceKeyCode(in: [:]) == nil)
    #expect(SystemHotkeys.nextSourceKeyCode(in: ["61": ["enabled": true]]) == nil)
}

