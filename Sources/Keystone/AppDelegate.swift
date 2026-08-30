import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let engine = RemapEngine()
    private let commandTapMonitor = CommandTapMonitor()
    private let updater = UpdaterController()
    private var settingsWindowController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private var toggleItem: NSMenuItem?
    private var signalSources: [DispatchSourceSignal] = []

    private static let onboardingCompletedKey = "onboarding.completed"

    func applicationDidFinishLaunching(_ notification: Notification) {
        /* A translocated launch relaunches itself from the real bundle —
           nothing else must start in this doomed instance. */
        if TranslocationHealer.healIfNeeded() { return }

        setUpMainMenu()
        updateStatusItemVisibility()

        /* Completion is only recorded when onboarding is finished properly,
           so an interrupted (or force-quit) run shows it again. */
        if !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)
            || CommandLine.arguments.contains("--onboarding")
        {
            showOnboarding()
        }

        AppPreferences.migrateTapPreferencesIfNeeded()
        commandTapMonitor.onTap = { key in
            switch AppPreferences.tapActions[key] {
            case .toggle: InputSourceSwitcher.toggle()
            case .select(let sourceID): InputSourceSwitcher.select(id: sourceID)
            case nil: break
            }
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
            self?.updateStatusItemVisibility()
            self?.syncMapping()
        }
        /* Coming back from System Settings after granting Input Monitoring:
           re-sync so the tap-alone monitor starts without a relaunch.
           syncMapping is idempotent, so spurious activations cost nothing. */
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.syncMapping()
        }

        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }

        /* Route SIGTERM/SIGINT (pkill, logout edge cases, ctrl-C under
           `swift run`) through the normal termination path, so the
           clear-on-quit below runs for them too. Only SIGKILL and crashes
           escape it — the next launch, toggle, or reboot sweeps up. */
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    /* The remap is active exactly while Keystone runs: quitting hands the
       keyboard back to stock macOS, so the app's presence is the whole
       story a user has to reason about. (Launch at login keeps it
       seamless across restarts.) */
    func applicationWillTerminate(_ notification: Notification) {
        engine.clear()
    }

    /* One place decides what the HID system, the event tap, and the menu
       should say, so the toggle, Settings, and the engine never drift. */
    private func syncMapping() {
        let destination = AppPreferences.destination
        if AppPreferences.isRemapEnabled {
            engine.apply(destination)
        } else {
            engine.clear()
        }

        /* Modifier-tap switching is independent of the Caps Lock remap: it
           never touches the HID mapping, only observes. */
        let tapActions = AppPreferences.tapActions
        if tapActions.isEmpty {
            commandTapMonitor.stop()
        } else {
            commandTapMonitor.watched = Set(tapActions.keys)
            if !commandTapMonitor.start() {
                NSLog("Keystone: event tap unavailable (Input Monitoring not granted?)")
            }
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

    /* Launching the app again while it's already running sends "reopen" to
       the live instance. With the menu bar icon hidden this is the only way
       back into the UI, so surface Settings (which also puts the app in the
       Dock via updateActivationPolicy). */
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        if AppPreferences.isMenuBarIconHidden {
            openSettings()
        }
        return false
    }

    /* An accessory app has no visible menu bar, but ⌘-key equivalents are
       still dispatched through the main menu — without one, ⌘W/⌘Q do
       nothing in the settings window. The menu also becomes visible for
       real whenever the app temporarily joins the Dock (regular policy). */
    private func setUpMainMenu() {
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(updater.makeMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "Quit Keystone",
                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            NSMenuItem(
                title: "Close Window",
                action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(
            NSMenuItem(
                title: "Minimize",
                action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))

        let mainMenu = NSMenu()
        for submenu in [appMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        NSApp.mainMenu = mainMenu
    }

    private func updateStatusItemVisibility() {
        if AppPreferences.isMenuBarIconHidden {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            toggleItem = nil
        } else if statusItem == nil {
            setUpStatusItem()
        }
        updateActivationPolicy()
    }

    private var isSettingsWindowVisible: Bool {
        settingsWindowController?.window?.isVisible == true
    }

    /* Dock presence: the app normally stays invisible (accessory policy),
       but while the menu bar icon is hidden AND Settings is open there would
       be no sign the app is running — so it joins the Dock for the duration
       and leaves again when the settings window closes. */
    private func updateActivationPolicy() {
        let wantsDock = AppPreferences.isMenuBarIconHidden && isSettingsWindowVisible
        let policy: NSApplication.ActivationPolicy = wantsDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        /* Flipping the policy can drop activation; keep Settings in front. */
        if isSettingsWindowVisible {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        }
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
            if let window = settingsWindowController?.window {
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification, object: window, queue: .main
                ) { [weak self] _ in
                    /* isVisible is still true inside willClose; re-evaluate
                       (and leave the Dock) on the next runloop cycle. */
                    DispatchQueue.main.async { self?.updateActivationPolicy() }
                }
            }
        }
        /* Accessory apps don't come forward on their own — activate first or
           the window opens behind the current app. */
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        updateActivationPolicy()
    }
}
