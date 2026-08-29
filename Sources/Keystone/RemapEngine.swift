import AppKit
import IOKit

/* Books the mapping into the HID event system by driving /usr/bin/hidutil —
   Apple's own tool, so there is no private API to break and no permission
   to request. Once set, the kernel rewrites Caps Lock on its own; this
   process sits idle.

   The mapping persists until reboot but not always through a keyboard
   (re)appearing — a Bluetooth keyboard waking, a USB replug — so the engine
   also watches HID device publications (plain IOKit matching notifications,
   no Input Monitoring TCC involved: nothing here reads input) plus wake
   from sleep, and re-asserts. Setting the property is idempotent and takes
   a few milliseconds, so over-asserting is harmless. */
final class RemapEngine {
    private var onDeviceChurn: (() -> Void)?
    private var pendingReassert: DispatchWorkItem?
    private var notifyPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0

    func apply(_ key: KeyRemap.FunctionKey) {
        /* Sweep everything first: 1.0.0 (and hand-run hidutil) installed
           the mapping on every HID service, media-key translators included;
           the unscoped clear removes those leftovers on upgrade before the
           properly scoped mapping goes in. Cheap and idempotent, so it's
           safe to repeat on every re-assert. */
        run(KeyRemap.clearArgument, matching: nil)
        run(KeyRemap.mappingArgument(to: key), matching: KeyRemap.keyboardMatchingArgument)
    }

    func clear() {
        /* Unscoped on purpose, for the same leftover-sweeping reason. */
        run(KeyRemap.clearArgument, matching: nil)
    }

    /* Synchronous (hidutil returns in a few ms): apply() relies on the
       sweep landing before the scoped set. */
    private func run(_ mapping: String, matching: String?) {
        let hidutil = Process()
        hidutil.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        var arguments = ["property"]
        if let matching {
            arguments += ["--matching", matching]
        }
        arguments += ["--set", mapping]
        hidutil.arguments = arguments
        hidutil.standardOutput = FileHandle.nullDevice
        do {
            try hidutil.run()
            hidutil.waitUntilExit()
            if hidutil.terminationStatus != 0 {
                NSLog("Keystone: hidutil exited with \(hidutil.terminationStatus)")
            }
        } catch {
            NSLog("Keystone: failed to launch hidutil: \(error)")
        }
    }

    /// Starts re-asserting via `reassert` whenever a HID device is published
    /// or the machine wakes. Call once.
    func startWatching(reassert: @escaping () -> Void) {
        onDeviceChurn = reassert

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleReassert()
        }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        notifyPort = port

        /* Any IOHIDDevice publication triggers a (debounced) re-assert;
           filtering for keyboards specifically isn't worth the extra IOKit
           plumbing when a spurious re-assert costs nothing. */
        let callback: IOServiceMatchingCallback = { context, iterator in
            guard let context else { return }
            let engine = Unmanaged<RemapEngine>.fromOpaque(context).takeUnretainedValue()
            RemapEngine.drain(iterator)
            engine.scheduleReassert()
        }
        let result = IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, IOServiceMatching("IOHIDDevice"),
            callback, Unmanaged.passUnretained(self).toOpaque(), &matchedIterator)
        guard result == KERN_SUCCESS else {
            NSLog("Keystone: HID matching notification failed (\(result))")
            return
        }
        /* The notification only arms once the existing matches are drained —
           and those are the already-present devices, which need no action. */
        Self.drain(matchedIterator)
    }

    /* Devices tend to publish in bursts (one keyboard is several HID
       services); coalesce to one re-assert. */
    private func scheduleReassert() {
        pendingReassert?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onDeviceChurn?() }
        pendingReassert = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }
}
