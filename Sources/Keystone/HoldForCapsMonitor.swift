import AppKit
import Carbon
import IOKit.hid
import IOKit.hidsystem

/* Opt-in "hold for real Caps Lock", built to keep the tap's zero delay:
   the remapped key's events pass through untouched, so a quick tap still
   switches the instant it goes down (via the System Settings shortcut,
   exactly as without this feature). The monitor only OBSERVES: on key-down
   it remembers the input source the press started on; if the key is still
   down half a second later, it toggles the system Caps Lock state (LED
   and all, via IOHIDSetModifierLockState) and hops the input source back
   to the remembered one — undoing the switch the key-down performed. The
   input menu flickers for the length of the hold; that is the whole cost.

   Observing keystrokes is what the lone-tap switcher already does, so
   this reuses the same Input Monitoring permission. Without the grant,
   start() fails and everything behaves as if the feature were off. */
final class HoldForCapsMonitor {
    /// The destination key's virtual keycode (KeyRemap.FunctionKey.keyCode).
    var keyCode: Int64 = 0x50

    /* Long enough that fast tap-switchers never trip it, short enough
       that engaging Caps Lock doesn't feel like a wait. */
    private static let holdThreshold: TimeInterval = 0.5

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingHold: DispatchWorkItem?
    /// The source the press started on, captured before the system
    /// shortcut (which runs after this head-inserted tap) switches away.
    private var sourceAtPress: String?
    /// The Caps Lock state applied at the hold threshold, re-applied just
    /// after key-up: the pressing keyboard's driver ignores state written
    /// mid-press (it kept "winning" and ending up the one keyboard with
    /// Caps Lock off), so the write is repeated once the press is over.
    private var capsTarget: Bool?
    /* The pressing keyboard's driver keeps re-asserting its own LED while
       the key is down; out-shouting it every 60ms keeps the light on from
       the moment the hold engages. */
    private var ledRefresh: Timer?
    /* True while Caps Lock is on BECAUSE OF a hold. While engaged, a tap
       still switches the input source but must never end Caps Lock — yet
       the switch knocks caps off the tapped keyboard (the Korean input
       method and the keyboard driver both meddle with it). So every tap
       during engagement is followed by a re-assert, and only the next
       hold turns Caps Lock off. */
    private var capsEngaged = false

    static var hasPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestPermission() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Returns false when the tap can't be created — in practice, when
    /// Input Monitoring hasn't been granted.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            if let context {
                Unmanaged<HoldForCapsMonitor>.fromOpaque(context)
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
        pendingHold?.cancel()
        pendingHold = nil
        sourceAtPress = nil
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
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            /* The system pauses taps it thinks are stuck; resume. */
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

        case .keyDown, .keyUp:
            guard event.getIntegerValueField(.keyboardEventKeycode) == keyCode else {
                return
            }
            /* Chords (⌘F19 and friends) are someone else's shortcut.
               maskSecondaryFn is deliberately not checked: macOS stamps it
               on every function-key event, the remapped key included. */
            let modifiers: CGEventFlags = [
                .maskShift, .maskControl, .maskAlternate, .maskCommand,
            ]
            guard event.flags.intersection(modifiers).isEmpty else { return }

            if type == .keyDown {
                /* Autorepeats of the held key carry no new information. */
                guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
                    return
                }
                sourceAtPress = Self.currentSourceID()
                capsTarget = nil
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    /* LED only at the threshold: writing the STATE while
                       the key is down is rejected by the pressing
                       keyboard's driver AND makes it stomp the LED — the
                       engage-flicker. State lands at key-up instead. */
                    let target = CapsLockState.targetForToggle()
                    self.capsTarget = target
                    self.capsEngaged = target
                    CapsLockState.setLEDs(target)
                    let timer = Timer(timeInterval: 0.06, repeats: true) { _ in
                        CapsLockState.setLEDs(target)
                    }
                    RunLoop.main.add(timer, forMode: .common)
                    self.ledRefresh = timer
                    /* Undo the switch the key-down performed: back to the
                       language the hold started on. */
                    if let source = self.sourceAtPress {
                        InputSourceSwitcher.select(id: source)
                    }
                }
                pendingHold = work
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + Self.holdThreshold, execute: work)
            } else {
                pendingHold?.cancel()
                pendingHold = nil
                sourceAtPress = nil
                ledRefresh?.invalidate()
                ledRefresh = nil
                if let target = capsTarget {
                    capsTarget = nil
                    /* A beat after the release, so the write lands once the
                       driver has finished its own key-up bookkeeping. */
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        CapsLockState.apply(target)
                    }
                } else if capsEngaged {
                    /* A tap while engaged: the input-source switch it
                       triggered knocks caps off the tapped keyboard, so
                       put everything back — immediately, and twice more,
                       because the just-released keyboard's driver rejects
                       writes for a beat after the key transaction. The
                       first shot that lands closes the lowercase gap.
                       (Async: apply spawns hidutil, too slow for a tap
                       callback.) */
                    DispatchQueue.main.async { CapsLockState.apply(true) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        [weak self] in
                        guard let self, self.capsEngaged else { return }
                        CapsLockState.apply(true)
                    }
                    /* Last shot doubles as the disengage check: caps gone
                       everywhere despite the re-asserts means some other
                       hand turned it off — accept that instead of
                       fighting the user. */
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        [weak self] in
                        guard let self, self.capsEngaged else { return }
                        if CapsLockState.targetForToggle() {
                            self.capsEngaged = false
                        } else {
                            CapsLockState.apply(true)
                        }
                    }
                }
            }

        default:
            break
        }
    }

    private static func currentSourceID() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return unsafeBitCast(pointer, to: CFString.self) as String
    }
}

/* Caps Lock state is tracked PER KEYBOARD: every keyboard service holds
   its own HIDCapsLockState, LED included. The legacy system-wide setter
   (IOHIDSetModifierLockState) reaches every keyboard EXCEPT the one being
   held — its driver promptly re-asserts its own state, which made the
   first attempt flash the pressing keyboard's LED and leave Caps Lock on
   only on the OTHER keyboard. Setting the property on every keyboard
   service instead — the same scoping as the remap itself — keeps all of
   them, and their LEDs, in agreement. */
enum CapsLockState {
    /// What the next toggle would set, without setting it.
    static func targetForToggle() -> Bool { !isAnyOn }

    @discardableResult
    static func toggle() -> Bool {
        let on = !isAnyOn
        apply(on)
        return on
    }

    /* Three layers, kept in agreement: the per-keyboard properties own
       each keyboard's caps behavior, the legacy system-wide state is what
       the event system re-syncs devices FROM when the next key event
       flows, and the LED elements are driven directly — the one channel
       the pressing keyboard honors mid-press, so the light comes on the
       moment the hold engages instead of after the release. */
    static func apply(_ on: Bool) {
        setAll(on)
        setGlobal(on)
        setLEDs(on)
    }

    /* Straight to the hardware: HID output elements (LED page, Caps Lock
       usage) on every keyboard. Failures are silent — the key-up state
       re-assert still brings the LED along, just later. */
    private static let ledManager: IOHIDManager = {
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(
            manager,
            [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6] as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return manager
    }()

    static func setLEDs(_ on: Bool) {
        guard let devices = IOHIDManagerCopyDevices(ledManager) as? Set<AnyHashable>
        else { return }
        let matching = [kIOHIDElementUsagePageKey: 0x08, kIOHIDElementUsageKey: 0x02]
        for anyDevice in devices {
            let device = anyDevice as! IOHIDDevice
            let elements =
                IOHIDDeviceCopyMatchingElements(
                    device, matching as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone))
                as? [IOHIDElement] ?? []
            for element in elements {
                let value = IOHIDValueCreateWithIntegerValue(
                    kCFAllocatorDefault, element, 0, on ? 1 : 0)
                IOHIDDeviceSetValue(device, element, value)
            }
        }
    }

    private static let systemConnection: io_connect_t = {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        var connect: io_connect_t = 0
        guard service != 0,
            IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect)
                == KERN_SUCCESS
        else { return 0 }
        return connect
    }()

    private static func setGlobal(_ on: Bool) {
        guard systemConnection != 0 else { return }
        IOHIDSetModifierLockState(systemConnection, Int32(kIOHIDCapsLockState), on)
    }

    /* Mixed states (one keyboard on, another off — e.g. toggled by another
       tool) normalize to "all off" first. */
    private static var isAnyOn: Bool {
        guard
            let output = runHidutil([
                "property", "--matching", KeyRemap.keyboardMatchingArgument,
                "--get", "HIDCapsLockState",
            ])
        else { return false }
        return output.split(separator: "\n").contains { line in
            line.split(separator: " ").last == "1"
        }
    }

    private static func setAll(_ on: Bool) {
        _ = runHidutil([
            "property", "--matching", KeyRemap.keyboardMatchingArgument,
            "--set", #"{"HIDCapsLockState":\#(on)}"#,
        ])
    }

    private static func runHidutil(_ arguments: [String]) -> String? {
        let hidutil = Process()
        hidutil.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        hidutil.arguments = arguments
        let pipe = Pipe()
        hidutil.standardOutput = pipe
        do {
            try hidutil.run()
        } catch {
            NSLog("Keystone: failed to launch hidutil: \(error)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        hidutil.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
