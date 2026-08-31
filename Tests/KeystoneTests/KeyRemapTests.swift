import Foundation
import Testing

@testable import Keystone

@Test func capsLockUsageIsTheHIDKeyboardPage() {
    #expect(KeyRemap.capsLockUsage == 0x7_0000_0039)
}

@Test func functionKeyUsagesAreContiguousFromF13() {
    #expect(KeyRemap.FunctionKey.f13.usage == 0x7_0000_0068)
    #expect(KeyRemap.FunctionKey.f19.usage == 0x7_0000_006E)
    #expect(KeyRemap.FunctionKey.f20.usage == 0x7_0000_006F)
}

@Test func mappingArgumentIsValidJSONWithTheRightPair() throws {
    let argument = KeyRemap.mappingArgument(to: .f19)
    let object = try JSONSerialization.jsonObject(with: Data(argument.utf8)) as? [String: Any]
    let mappings = try #require(object?["UserKeyMapping"] as? [[String: Any]])
    #expect(mappings.count == 1)
    #expect(mappings[0]["HIDKeyboardModifierMappingSrc"] as? UInt64 == KeyRemap.capsLockUsage)
    #expect(
        mappings[0]["HIDKeyboardModifierMappingDst"] as? UInt64
            == KeyRemap.FunctionKey.f19.usage)
}

@Test func tapActionsRoundTripThroughStorage() {
    #expect(AppPreferences.TapAction(stored: "toggle") == .toggle)
    #expect(
        AppPreferences.TapAction(stored: "select:com.apple.keylayout.ABC")
            == .select(sourceID: "com.apple.keylayout.ABC"))
    #expect(AppPreferences.TapAction(stored: "nonsense") == nil)
    #expect(AppPreferences.TapAction.toggle.stored == "toggle")
    #expect(
        AppPreferences.TapAction.select(sourceID: "a.b").stored == "select:a.b")
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
