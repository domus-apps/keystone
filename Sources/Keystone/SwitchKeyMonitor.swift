import AppKit
import Carbon.HIToolbox
import IOKit.hid

/* The release-triggered Keystone path: a modifier (⌘ or ⌥, either side)
   pressed and released ALONE — no other key or modifier in between —
   fires on the release, via a listen-only CGEvent tap. The tap observes
   only what the detection needs: modifier changes plus the fact THAT a
   key went down mid-hold (to cancel), never what the key was. (The
   press-triggered path lives in PhysicalKeyMonitor.)

   Watching keystrokes at all is why this is opt-in and requires the Input
   Monitoring permission. Where event taps go silent — secure input,
   notably password fields and Terminal's Secure Keyboard Entry — the
   trigger doesn't fire. */
final class SwitchKeyMonitor {
    var onTap: ((KeyRemap.Key) -> Void)?

    /* Which physical modifiers count as a release-switch. Changing this
       while running takes effect on the next press. */
    var releaseKeys: Set<KeyRemap.Key> = []

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /* The keycode of the modifier that went down alone; cleared by whatever
       ends the gesture — a clean release of the same key fires. */
    private var armedKeycode: Int64?

    /* One watchable modifier: its keycode, its device-specific flag bit
       (NX_DEVICE*KEYMASK — which physical key a flags event is about), its
       sibling's bit (the same modifier on the other side), and its class
       flag. Everything the alone-check needs. */
    private struct WatchedKey {
        let key: KeyRemap.Key
        let keycode: Int
        let ownBit: UInt64
        let siblingBit: UInt64
        let classFlag: CGEventFlags
    }

    private static let watchedKeys: [WatchedKey] = [
        WatchedKey(
            key: .leftCommand, keycode: kVK_Command, ownBit: 0x08, siblingBit: 0x10,
            classFlag: .maskCommand),
        WatchedKey(
            key: .rightCommand, keycode: kVK_RightCommand, ownBit: 0x10, siblingBit: 0x08,
            classFlag: .maskCommand),
        WatchedKey(
            key: .leftOption, keycode: kVK_Option, ownBit: 0x20, siblingBit: 0x40,
            classFlag: .maskAlternate),
        WatchedKey(
            key: .rightOption, keycode: kVK_RightOption, ownBit: 0x40, siblingBit: 0x20,
            classFlag: .maskAlternate),
    ]

    /* Every modifier class the tap can see; a lone tap must carry none of
       them beyond the tapped key's own class. */
    private static let allClasses: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn,
    ]

    static var hasPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /* Triggers the system prompt on first ask; afterwards macOS stays
       silent and System Settings is the only path. */
    static func requestPermission() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Returns false when the tap can't be created — in practice, when
    /// Input Monitoring hasn't been granted.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            if let context {
                Unmanaged<SwitchKeyMonitor>.fromOpaque(context)
                    .takeUnretainedValue().handle(type: type, event: event)
            }
            /* Listen-only tap: the return value is ignored, nothing is
               modified or blocked. */
            return Unmanaged.passUnretained(event)
        }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        return true
    }

    func stop() {
        armedKeycode = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    deinit {
        stop()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .keyDown:
            /* A real key while a modifier is held: a shortcut, not a tap. */
            armedKeycode = nil

        case .flagsChanged:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            guard
                let watched = Self.watchedKeys.first(where: { $0.keycode == keycode }),
                releaseKeys.contains(watched.key)
            else {
                /* Some other modifier (or an unwatched one) moved mid-hold:
                   chord, not a tap. */
                armedKeycode = nil
                return
            }

            let flags = event.flags
            if flags.rawValue & watched.ownBit != 0 {
                /* Arm only for this key alone — not its sibling, and no
                   modifier of any other class. */
                let alone =
                    flags.rawValue & watched.siblingBit == 0
                    && flags.intersection(Self.allClasses.subtracting(watched.classFlag)).isEmpty
                armedKeycode = alone ? keycode : nil
            } else if armedKeycode == keycode {
                armedKeycode = nil
                onTap?(watched.key)
            }

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            /* The system pauses taps it thinks are stuck; resume. */
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

        default:
            break
        }
    }
}
