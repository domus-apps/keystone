import AppKit
import ServiceManagement

// MARK: - Window

enum SettingsPane: Int, CaseIterable {
    case general
    case remap

    var title: String {
        switch self {
        case .general: "General"
        case .remap: "Remapping"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .remap: "keyboard"
        }
    }
}

/* System Settings-style window: full-height sidebar on the left, panes on
   the right. The style mask keeps all three traffic lights live (zoom stays
   disabled by macOS itself while the window is not resizable-by-content,
   matching native settings windows). */
final class SettingsWindowController: NSWindowController {
    private let splitViewController: SettingsSplitViewController

    init(updater: UpdaterController) {
        splitViewController = SettingsSplitViewController(updater: updater)
        let window = NSWindow(contentViewController: splitViewController)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        /* A toolbar (even an empty one) is required for the full-height
           sidebar look. The tall unified style centers the traffic lights
           in a roomier title bar (like Xcode's settings window) instead of
           pinning them to the top-left corner. */
        window.toolbarStyle = .unified
        let toolbar = NSToolbar()
        /* An empty toolbar defaults to .iconAndLabel, which inflates the
           unified title bar to 66pt; .iconOnly gives the standard 52pt that
           Xcode's settings window uses. */
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 640, height: 440))
        window.center()

        super.init(window: window)
        splitViewController.onPaneChange = { [weak window] pane in
            window?.title = pane.title
        }
        splitViewController.show(.general)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

final class SettingsSplitViewController: NSSplitViewController {
    var onPaneChange: ((SettingsPane) -> Void)?

    private let sidebar = SettingsSidebarViewController()
    private let paneContainer = NSViewController()
    private let generalPane: GeneralPaneViewController
    private let remapPane = RemapPaneViewController()
    private var currentPane: NSViewController?

    init(updater: UpdaterController) {
        generalPane = GeneralPaneViewController(updater: updater)
        super.init(nibName: nil, bundle: nil)

        paneContainer.view = NSView()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 160
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: paneContainer))

        sidebar.onSelect = { [weak self] pane in
            self?.show(pane)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ pane: SettingsPane) {
        let next: NSViewController =
            switch pane {
            case .general: generalPane
            case .remap: remapPane
            }
        guard next !== currentPane else { return }

        if let currentPane {
            currentPane.view.removeFromSuperview()
            currentPane.removeFromParent()
        }
        paneContainer.addChild(next)
        next.view.translatesAutoresizingMaskIntoConstraints = false
        paneContainer.view.addSubview(next.view)
        NSLayoutConstraint.activate([
            next.view.topAnchor.constraint(equalTo: paneContainer.view.topAnchor),
            next.view.bottomAnchor.constraint(equalTo: paneContainer.view.bottomAnchor),
            next.view.leadingAnchor.constraint(equalTo: paneContainer.view.leadingAnchor),
            next.view.trailingAnchor.constraint(equalTo: paneContainer.view.trailingAnchor),
        ])
        currentPane = next

        sidebar.select(pane)
        onPaneChange?(pane)
    }
}

// MARK: - Sidebar

final class SettingsSidebarViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate
{
    var onSelect: ((SettingsPane) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    /* Extra top inset below the safe area. Zero, like Xcode's settings
       sidebar: the first row sits flush against the title bar boundary. */
    private static let scrollEdgeFadeClearance: CGFloat = 0

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowSizeStyle = .default
        tableView.allowsEmptySelection = false
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        /* Managed manually in viewDidLayout: the automatic inset stops at
           the safe area, which leaves the first row inside the fade. */
        scrollView.automaticallyAdjustsContentInsets = false
        view = scrollView

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateScrollEdgeFade()
        }
    }

    /* The soft scroll-edge fade (macOS 26) is not scroll-aware: its gradient
       backdrop hangs ~10pt below the title bar at all times, dimming a first
       row that sits flush against the boundary even when nothing is scrolled
       under the bar. Mirror Xcode's settings sidebar instead: fade only while
       content is actually scrolled under. The pocket is a private AppKit view
       (NSScrollPocket), so this is a defensive class-name lookup — if AppKit
       renames it, the system's default behavior simply returns. */
    private func updateScrollEdgeFade() {
        let restTop = -scrollView.contentInsets.top
        let atRest = scrollView.contentView.bounds.minY <= restTop + 0.5
        for subview in scrollView.subviews
        where String(describing: type(of: subview)) == "NSScrollPocket" {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                subview.animator().alphaValue = atRest ? 0 : 1
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        /* The pocket can appear after the first layout pass, so re-evaluate
           on every layout, not only when the inset changes. */
        defer { updateScrollEdgeFade() }
        let top = view.safeAreaInsets.top + Self.scrollEdgeFadeClearance
        guard scrollView.contentInsets.top != top else { return }
        let wasAtTop = scrollView.contentView.bounds.minY <= -scrollView.contentInsets.top
        scrollView.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        if wasAtTop {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: -top))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func select(_ pane: SettingsPane) {
        guard tableView.selectedRow != pane.rawValue else { return }
        tableView.selectRowIndexes(IndexSet(integer: pane.rawValue), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        SettingsPane.allCases.count
    }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard let pane = SettingsPane(rawValue: row) else { return nil }

        let cell = NSTableCellView()
        let imageView = NSImageView(
            image: NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: nil)
                ?? NSImage())
        let textField = NSTextField(labelWithString: pane.title)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageView)
        cell.addSubview(textField)
        cell.imageView = imageView
        cell.textField = textField
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let pane = SettingsPane(rawValue: tableView.selectedRow) else { return }
        onSelect?(pane)
    }
}

// MARK: - General pane

final class GeneralPaneViewController: NSViewController {
    private let updater: UpdaterController

    init(updater: UpdaterController) {
        self.updater = updater
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private lazy var launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Launch at login", target: self,
        action: #selector(toggleLaunchAtLogin))

    private lazy var hideMenuBarIconCheckbox = NSButton(
        checkboxWithTitle: "Hide menu bar icon", target: self,
        action: #selector(toggleHideMenuBarIcon))

    /* SMAppService needs a real app bundle; a bare `swift run` binary has no
       bundle identifier to register. */
    private var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    override func loadView() {
        var views: [NSView] = [launchAtLoginCheckbox]
        if isBundledApp {
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginCheckbox.isEnabled = false
            views.append(
                SettingsNote.make("Available in the bundled app only (Scripts/bundle.sh)."))
        }

        hideMenuBarIconCheckbox.state = AppPreferences.isMenuBarIconHidden ? .on : .off
        views.append(hideMenuBarIconCheckbox)
        let hideNote = SettingsNote.make(
            "While hidden, launch Keystone again to open Settings. "
                + "The app appears in the Dock only while this window is open.")
        views.append(hideNote)

        /* Updates: mirror the menu bar's Check for Updates here too, the
           suite-standard spot. "dev" for `swift run` builds, which have no
           Info.plist — same fallback as the status menu's title. */
        views.append(updater.makeCheckButton())
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = (info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""
        views.append(SettingsNote.make("Version \(version)\(build)"))

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(20, after: hideNote)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view = SettingsNote.paneContainer(wrapping: stack)

        /* The menu bar has no toggle for this, but stay in sync anyway in
           case a future path changes the preference elsewhere. */
        NotificationCenter.default.addObserver(
            forName: AppPreferences.changed, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.hideMenuBarIconCheckbox.state =
                AppPreferences.isMenuBarIconHidden ? .on : .off
        }
    }

    @objc private func toggleHideMenuBarIcon() {
        AppPreferences.isMenuBarIconHidden.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginCheckbox.state = launchAtLoginCheckbox.state == .on ? .off : .on
            NSLog("Keystone: launch-at-login change failed: \(error)")
        }
    }
}

// MARK: - Remapping pane

final class RemapPaneViewController: NSViewController {
    private lazy var remapCheckbox = NSButton(
        checkboxWithTitle: "Remap Caps Lock to:", target: self,
        action: #selector(toggleRemap))

    /* Each spare function key by name; the selection maps back through
       representedObject. */
    private lazy var keyPopUp: NSPopUpButton = {
        let popUp = NSPopUpButton()
        for key in KeyRemap.FunctionKey.allCases {
            let item = NSMenuItem(title: key.title, action: nil, keyEquivalent: "")
            item.representedObject = key
            popUp.menu?.addItem(item)
        }
        popUp.target = self
        popUp.action = #selector(changeKey)
        return popUp
    }()

    /* The tap-key options by name; selections map back through
       representedObject. */
    private lazy var commandKeysPopUp = Self.makeSidePopUp(
        target: self, action: #selector(changeCommandKeys))
    private lazy var optionKeysPopUp = Self.makeSidePopUp(
        target: self, action: #selector(changeOptionKeys))

    private static func makeSidePopUp(target: AnyObject, action: Selector) -> NSPopUpButton {
        let popUp = NSPopUpButton()
        for side in AppPreferences.ModifierSide.allCases {
            let item = NSMenuItem(title: title(for: side), action: nil, keyEquivalent: "")
            item.representedObject = side
            popUp.menu?.addItem(item)
        }
        popUp.target = target
        popUp.action = action
        return popUp
    }

    private let permissionNote = SettingsNote.make(
        "Input Monitoring isn't granted yet — allow Keystone under Privacy & "
            + "Security › Input Monitoring. The system prompt appears only on the "
            + "first ask.")
    private lazy var permissionButton = NSButton(
        title: "Open Privacy & Security Settings…", target: self,
        action: #selector(openInputMonitoringSettings))

    private static func title(for side: AppPreferences.ModifierSide) -> String {
        switch side {
        case .off: "Off"
        case .left: "Left"
        case .right: "Right"
        case .both: "Both"
        }
    }

    override func loadView() {
        remapCheckbox.state = AppPreferences.isRemapEnabled ? .on : .off
        keyPopUp.selectItem(
            at: KeyRemap.FunctionKey.allCases.firstIndex(of: AppPreferences.destination) ?? 0)
        let remapRow = NSStackView(views: [remapCheckbox, keyPopUp])
        remapRow.orientation = .horizontal

        let remapNote = SettingsNote.make(
            "The remap lives in macOS's HID system — instant, and no process touches "
                + "your keystrokes. Turning it off, or quitting Keystone, restores "
                + "stock Caps Lock immediately.")

        let shortcutNote = SettingsNote.make(
            "For delay-free input switching, bind the shortcut to the same key: "
                + "System Settings › Keyboard › Keyboard Shortcuts… › Input Sources › "
                + "“Select next source in Input menu”, then press Caps Lock to record it.")
        let openShortcuts = NSButton(
            title: "Open Keyboard Settings…", target: self,
            action: #selector(openKeyboardSettings))

        syncCommandControls()
        let tapHeader = NSTextField(
            labelWithString: "Switch input source when tapped alone:")
        let commandKeysRow = NSStackView(views: [
            NSTextField(labelWithString: "Command ⌘:"), commandKeysPopUp,
        ])
        commandKeysRow.orientation = .horizontal
        let optionKeysRow = NSStackView(views: [
            NSTextField(labelWithString: "Option ⌥:"), optionKeysPopUp,
        ])
        optionKeysRow.orientation = .horizontal

        let commandNote = SettingsNote.make(
            "A modifier pressed and released with nothing else in between switches "
                + "the input source; every shortcut using it keeps working. Watching "
                + "for that lone tap is the one Keystone feature that observes keys, "
                + "so it needs the Input Monitoring permission.")

        let stack = NSStackView(views: [
            remapRow, remapNote, shortcutNote, openShortcuts,
            tapHeader, commandKeysRow, optionKeysRow, commandNote,
            permissionNote, permissionButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(20, after: remapNote)
        stack.setCustomSpacing(20, after: openShortcuts)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view = SettingsNote.paneContainer(wrapping: stack)
        syncCommandControls()

        /* The menu bar toggle changes the same preference; stay in sync
           while the pane is open. */
        NotificationCenter.default.addObserver(
            forName: AppPreferences.changed, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.remapCheckbox.state = AppPreferences.isRemapEnabled ? .on : .off
            self.keyPopUp.selectItem(
                at: KeyRemap.FunctionKey.allCases.firstIndex(of: AppPreferences.destination)
                    ?? 0)
            self.syncCommandControls()
        }
    }

    private func syncCommandControls() {
        let commandKeys = AppPreferences.commandSwitchKeys
        let optionKeys = AppPreferences.optionSwitchKeys
        commandKeysPopUp.selectItem(
            at: AppPreferences.ModifierSide.allCases.firstIndex(of: commandKeys) ?? 0)
        optionKeysPopUp.selectItem(
            at: AppPreferences.ModifierSide.allCases.firstIndex(of: optionKeys) ?? 0)

        let needsPermission =
            (commandKeys != .off || optionKeys != .off) && !CommandTapMonitor.hasPermission
        permissionNote.isHidden = !needsPermission
        permissionButton.isHidden = !needsPermission
    }

    /* Toggle the preference rather than reading the checkbox: the action
       can fire before AppKit flips the control's state (notably under
       accessibility-driven clicks), and the observer above re-syncs the
       checkbox from the preference anyway. */
    @objc private func toggleRemap() {
        AppPreferences.isRemapEnabled.toggle()
    }

    @objc private func changeKey() {
        guard let key = keyPopUp.selectedItem?.representedObject as? KeyRemap.FunctionKey
        else { return }
        AppPreferences.destination = key
    }

    @objc private func changeCommandKeys() {
        guard
            let side = commandKeysPopUp.selectedItem?.representedObject
                as? AppPreferences.ModifierSide
        else { return }
        AppPreferences.commandSwitchKeys = side
        requestPermissionIfNeeded()
    }

    @objc private func changeOptionKeys() {
        guard
            let side = optionKeysPopUp.selectedItem?.representedObject
                as? AppPreferences.ModifierSide
        else { return }
        AppPreferences.optionSwitchKeys = side
        requestPermissionIfNeeded()
    }

    private func requestPermissionIfNeeded() {
        if AppPreferences.commandSwitchKeys != .off || AppPreferences.optionSwitchKeys != .off,
            !CommandTapMonitor.hasPermission
        {
            CommandTapMonitor.requestPermission()
        }
        syncCommandControls()
    }

    @objc private func openKeyboardSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openInputMonitoringSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security"
                    + "?Privacy_ListenEvent")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Shared pane furniture

enum SettingsNote {
    /* The small secondary explainer used across panes. */
    static func make(_ text: String) -> NSTextField {
        let note = NSTextField(wrappingLabelWithString: text)
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        return note
    }

    /* Standard pane chrome: content pinned to the top-left under the
       title bar, capped at a readable width — and scrollable, for panes
       taller than the window. */
    static func paneContainer(wrapping stack: NSStackView) -> NSView {
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        /* Under .fullSizeContentView the scroll view runs beneath the title
           bar; the automatic inset keeps content (and the scroll range)
           below it, like every standard settings pane. */
        scroll.automaticallyAdjustsContentInsets = true

        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            /* Height comes from the content: the bottom padding below makes
               the document exactly as tall as the stack needs. */
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: document.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
        return scroll
    }

    /* Scroll documents want a top-left origin. */
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
