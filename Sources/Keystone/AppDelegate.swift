import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let engine = RemapEngine()
    private let updater = UpdaterController()
    private var settingsWindowController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private var toggleItem: NSMenuItem?

    private static let onboardingCompletedKey = "onboarding.completed"

    func applicationDidFinishLaunching(_ notification: Notification) {
        /* A translocated launch relaunches itself from the real bundle —
           nothing else must start in this doomed instance. */
        if TranslocationHealer.healIfNeeded() { return }

        setUpStatusItem()

        /* Completion is only recorded when onboarding is finished properly,
           so an interrupted (or force-quit) run shows it again. */
        if !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)
            || CommandLine.arguments.contains("--onboarding")
        {
            showOnboarding()
        }

        syncMapping()
        engine.startWatching { [weak self] in
            /* A keyboard appeared or the machine woke: the mapping may have
               been dropped with the device — assert it again. */
            if AppPreferences.isRemapEnabled {
                self?.engine.apply(AppPreferences.destination)
            }
        }
        NotificationCenter.default.addObserver(
            forName: AppPreferences.changed, object: nil, queue: .main
        ) { [weak self] _ in
            self?.syncMapping()
        }

        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }
    }

    /* Quit leaves the mapping in place on purpose: it lives in the HID
       system, costs nothing, and the user turned it on. Disabling the
       checkbox is the way to get stock Caps Lock back. */

    /* One place decides what the HID system and the menu should say, so
       the toggle, Settings, and the engine can never drift apart. */
    private func syncMapping() {
        let destination = AppPreferences.destination
        if AppPreferences.isRemapEnabled {
            engine.apply(destination)
        } else {
            engine.clear()
        }
        toggleItem?.state = AppPreferences.isRemapEnabled ? .on : .off
        toggleItem?.title = "Remap Caps Lock to \(destination.title)"
    }

    private func showOnboarding() {
        if onboardingController == nil {
            onboardingController = OnboardingWindowController { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
                self?.onboardingController = nil
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingController?.window?.makeKeyAndOrderFront(nil)
    }

    private func setUpStatusItem() {
        /* A fixed length instead of squareLength: square items are as wide
           as the menu bar is tall, which pads a ~18pt symbol with a lot of
           dead space. 20pt hugs the icon while keeping its natural size —
           the same width every Domus app uses. */
        let item = NSStatusBar.system.statusItem(withLength: 20)
        item.button?.image = NSImage(
            systemSymbolName: "capslock", accessibilityDescription: "Keystone")

        let menu = NSMenu()
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let about = NSMenuItem(title: "Keystone \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(.separator())
        let toggle = NSMenuItem(
            title: "Remap Caps Lock", action: #selector(toggleRemap), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleItem = toggle
        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(updater.makeMenuItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Keystone",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleRemap() {
        AppPreferences.isRemapEnabled.toggle()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(updater: updater)
        }
        /* Accessory apps don't come forward on their own — activate first or
           the window opens behind the current app. */
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}
