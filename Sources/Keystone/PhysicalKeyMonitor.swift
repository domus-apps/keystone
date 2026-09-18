import Foundation
import IOKit.hid

/* Watches physical keys at the HID device layer, through IOHIDManager —
   below the kernel's UserKeyMapping, so a key the remap has turned into
   "nothing" (KeyRemap.noEventUsage) is still seen here as the key it
   physically is (measured 2026-09-15: Caps Lock rerouted to no-event was
   silent at the CGEvent layer and present here as usage 0x39, 32/32
   presses). That is what makes the press-triggered Keystone path work
   without any function key existing for other software to collide with.

   Every press counts, held modifiers or not: a key rerouted to nothing has
   no other meaning for ⇧ or ⌥ to give it, and people do hit Caps Lock
   with Shift still down mid-word (the first build vetoed chords and that
   read as "switching randomly fails"). The system shortcut path behaves
   the same way.

   Passive only: the manager is opened without seizing, so the keyboard
   keeps working for everyone else. Needs the Input Monitoring permission
   (IOHIDRequestAccess is exactly this API's grant). Where secure input is
   on — password fields, Terminal's Secure Keyboard Entry — the HID layer
   goes quiet along with event taps, and watched keys do nothing. */
final class PhysicalKeyMonitor {
    /// A watched key went down.
    var onPress: ((KeyRemap.Key) -> Void)?
    /// A watched key came up.
    var onRelease: ((KeyRemap.Key) -> Void)?

    /* Which physical keys to report. Changing this while running takes
       effect on the next press. */
    var watched: Set<KeyRemap.Key> = []

    private var manager: IOHIDManager?

    private static func key(forUsage usage: UInt32) -> KeyRemap.Key? {
        KeyRemap.Key.allCases.first { $0.usage & 0xFFFF_FFFF == UInt64(usage) }
    }

    static var hasPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestPermission() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Returns false when the manager can't be opened — in practice, when
    /// Input Monitoring hasn't been granted.
    @discardableResult
    func start() -> Bool {
        guard manager == nil else { return true }
        guard Self.hasPermission else { return false }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let devices: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, devices as CFArray)
        /* Only the watchable keys' elements; everything else stays unread. */
        let elements: [[String: Any]] = KeyRemap.Key.allCases.map {
            [kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad, kIOHIDElementUsageKey: Int($0.usage & 0xFFFF_FFFF)]
        }
        IOHIDManagerSetInputValueMatchingMultiple(manager, elements as CFArray)

        let callback: IOHIDValueCallback = { context, _, _, value in
            guard let context else { return }
            Unmanaged<PhysicalKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                .handle(value: value)
        }
        IOHIDManagerRegisterInputValueCallback(
            manager, callback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return false
        }
        self.manager = manager
        return true
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    deinit {
        stop()
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad),
            let key = Self.key(forUsage: IOHIDElementGetUsage(element)),
            watched.contains(key)
        else { return }
        if IOHIDValueGetIntegerValue(value) != 0 {
            onPress?(key)
        } else {
            onRelease?(key)
        }
    }
}
