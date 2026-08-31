import Foundation

/* The remap model: Caps Lock rerouted to a spare function key inside the
   HID event system — the same UserKeyMapping property `hidutil` sets. The
   kernel does the rewriting, so no process ever touches a keystroke;
   Keystone only books the mapping in (and re-asserts it when the system
   forgets — see RemapEngine). Kept pure and value-typed so it's testable. */
enum KeyRemap {
    /// HID keyboard usages live on page 0x07; UserKeyMapping wants the
    /// 64-bit (page << 32 | usage) form.
    static let capsLockUsage: UInt64 = 0x7_0000_0039

    /// The spare keys worth offering: F13–F20 exist as usages on every
    /// keyboard but as physical keys on almost none, so nothing else
    /// competes for them. F19 is the conventional pick for this trick.
    enum FunctionKey: String, CaseIterable {
        case f13, f14, f15, f16, f17, f18, f19, f20

        /// F13 is usage 0x68; the rest follow contiguously.
        var usage: UInt64 {
            0x7_0000_0068 + UInt64(Self.allCases.firstIndex(of: self)!)
        }

        var title: String { rawValue.uppercased() }

        /// The key's virtual keycode (kVK_F13…kVK_F20) — what a CGEvent
        /// for the remapped key carries, for the hold-for-Caps-Lock tap.
        var keyCode: Int64 {
            switch self {
            case .f13: 105
            case .f14: 107
            case .f15: 113
            case .f16: 106
            case .f17: 64
            case .f18: 79
            case .f19: 80
            case .f20: 90
            }
        }
    }

    /// The `hidutil property --set` argument mapping Caps Lock to `key`.
    static func mappingArgument(to key: FunctionKey) -> String {
        """
        {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\(capsLockUsage),\
        "HIDKeyboardModifierMappingDst":\(key.usage)}]}
        """
    }

    /// The argument that removes every user mapping, restoring Caps Lock.
    static let clearArgument = #"{"UserKeyMapping":[]}"#

    /// `hidutil property --matching` filter restricting writes to actual
    /// keyboards (Generic Desktop page, Keyboard usage). Without it the
    /// mapping lands on every HID service in the system — including the
    /// Apple vendor services that translate the fn row into brightness and
    /// volume events, which a keyboard mapping visibly breaks.
    static let keyboardMatchingArgument = #"{"PrimaryUsagePage":1,"PrimaryUsage":6}"#
}
