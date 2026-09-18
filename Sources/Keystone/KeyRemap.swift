import Foundation

/* The remap model: a key rerouted to a spare function key inside the HID
   event system — the same UserKeyMapping property `hidutil` sets. The
   kernel does the rewriting, so no process ever touches a keystroke;
   Keystone only books the mapping in (and re-asserts it when the system
   forgets — see RemapEngine). Kept pure and value-typed so it's testable. */
enum KeyRemap {
    /// The physical keys Keystone can reroute. HID keyboard usages live on
    /// page 0x07; UserKeyMapping wants the 64-bit (page << 32 | usage) form.
    enum Key: String, CaseIterable {
        case capsLock, leftCommand, rightCommand, leftOption, rightOption

        var usage: UInt64 {
            switch self {
            case .capsLock: 0x7_0000_0039
            case .leftOption: 0x7_0000_00E2
            case .leftCommand: 0x7_0000_00E3
            case .rightOption: 0x7_0000_00E6
            case .rightCommand: 0x7_0000_00E7
            }
        }

        /// Modifiers can keep their modifier role and switch on a lone
        /// release instead of being rerouted; Caps Lock has no such role
        /// to keep, so it is always rerouted.
        var isModifier: Bool { self != .capsLock }

        var title: String {
            switch self {
            case .capsLock: L("Caps Lock")
            case .leftCommand: L("Left ⌘")
            case .rightCommand: L("Right ⌘")
            case .leftOption: L("Left ⌥")
            case .rightOption: L("Right ⌥")
            }
        }
    }

    /// Kept for the tests and the onboarding copy that name it.
    static let capsLockUsage: UInt64 = Key.capsLock.usage

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
        /// for the rerouted key carries, for the taps that watch it.
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

    /// Usage 0x00 on the keyboard page: "Reserved (no event indicated)".
    /// A key rerouted here produces nothing at all — no keycode, no
    /// modifier flag, no Caps Lock toggle or LED (measured 2026-09-15 with
    /// a CGEvent tap: silence). The physical press is still visible below
    /// the remap, at the HID device layer, which is where PhysicalKeyMonitor
    /// picks it up.
    static let noEventUsage: UInt64 = 0x7_0000_0000

    /// One rerouted key: to a function key the system can act on (the
    /// native path), or to nothing (`destination == nil`), leaving Keystone
    /// as the only party that sees the key.
    struct Mapping: Equatable {
        let key: Key
        let destination: FunctionKey?

        var destinationUsage: UInt64 { destination?.usage ?? KeyRemap.noEventUsage }
    }

    /// The `hidutil property --set` argument installing `mappings`. One
    /// call sets the whole list: UserKeyMapping replaces, never merges,
    /// so every rerouted key has to be in it.
    static func mappingArgument(_ mappings: [Mapping]) -> String {
        let pairs = mappings.map { mapping in
            #"{"HIDKeyboardModifierMappingSrc":\#(mapping.key.usage),"#
                + #""HIDKeyboardModifierMappingDst":\#(mapping.destinationUsage)}"#
        }
        return #"{"UserKeyMapping":[\#(pairs.joined(separator: ","))]}"#
    }

    /// The argument that removes every user mapping, restoring stock keys.
    static let clearArgument = #"{"UserKeyMapping":[]}"#

    /// `hidutil property --matching` filter restricting writes to actual
    /// keyboards (Generic Desktop page, Keyboard usage). Without it the
    /// mapping lands on every HID service in the system — including the
    /// Apple vendor services that translate the fn row into brightness and
    /// volume events, which a keyboard mapping visibly breaks.
    static let keyboardMatchingArgument = #"{"PrimaryUsagePage":1,"PrimaryUsage":6}"#
}
