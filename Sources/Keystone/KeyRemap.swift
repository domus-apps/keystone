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
}
