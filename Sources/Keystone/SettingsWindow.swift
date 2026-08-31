import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Window

enum SettingsPane: Int, CaseIterable {
    case general
    case remap

    var title: String {
        switch self {
        case .general: L("General")
        case .remap: L("Remapping")
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
    private let generalPane: NSViewController
    private let remapPane: NSViewController
    private var currentPane: NSViewController?

    init(updater: UpdaterController) {
        /* The panes are SwiftUI grouped Forms — the exact section-header +
           rounded-box arrangement Xcode's settings use — hosted inside the
           AppKit split chrome. */
        let model = SettingsModel(updater: updater)
        generalPane = NSHostingController(rootView: GeneralSettingsView(model: model))
        remapPane = NSHostingController(rootView: RemapSettingsView(model: model))
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

// MARK: - SwiftUI bridge

/* One shared model for both panes: preferences live in UserDefaults (via
   AppPreferences); this object just republishes their change notification
   so SwiftUI re-reads, and carries the pieces that aren't preferences
   (SMAppService, the updater, the input source list). */
final class SettingsModel: ObservableObject {
    let updater: UpdaterController
    @Published private(set) var enabledSources: [InputSourceSwitcher.Source] = []

    init(updater: UpdaterController) {
        self.updater = updater
        NotificationCenter.default.addObserver(
            forName: AppPreferences.changed, object: nil, queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /* SMAppService needs a real app bundle; a bare `swift run` binary has
       no bundle identifier to register. */
    var isBundledApp: Bool { Bundle.main.bundleIdentifier != nil }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Keystone: launch-at-login change failed: \(error)")
            }
            objectWillChange.send()
        }
    }

    var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = (info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""
        return version + build
    }

    /* The enabled-source list lives in System Settings and can change
       behind our back; panes refresh it on every appearance. */
    func refreshSources() {
        enabledSources = InputSourceSwitcher.enabledSources()
    }

    func binding<Value>(
        _ get: @escaping () -> Value, _ set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: get, set: set)
    }
}

// MARK: - General pane

struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle(
                        L("Launch at login"),
                        isOn: model.binding({ model.launchAtLogin }, { model.launchAtLogin = $0 })
                    )
                    .disabled(!model.isBundledApp)
                    if !model.isBundledApp {
                        Text(L("Available in the bundled app only (Scripts/bundle.sh)."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(
                        L("Hide menu bar icon"),
                        isOn: model.binding(
                            { AppPreferences.isMenuBarIconHidden },
                            { AppPreferences.isMenuBarIconHidden = $0 }))
                    Text(
                        L(
                            "While hidden, launch Keystone again to open Settings. The "
                                + "app appears in the Dock only while this window is open."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section(L("Updates")) {
                LabeledContent(L("Version"), value: model.versionLabel)
                Button(L("Check for Updates…")) {
                    model.updater.checkForUpdates()
                }
                .disabled(!model.updater.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Remapping pane

struct RemapSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(
                    L("Remap Caps Lock"),
                    isOn: model.binding(
                        { AppPreferences.isRemapEnabled },
                        { AppPreferences.isRemapEnabled = $0 }))
                Picker(
                    L("Destination key"),
                    selection: model.binding(
                        { AppPreferences.destination },
                        { AppPreferences.destination = $0 })
                ) {
                    ForEach(KeyRemap.FunctionKey.allCases, id: \.self) { key in
                        Text(key.title).tag(key)
                    }
                }
                .disabled(!AppPreferences.isRemapEnabled)

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(
                        L("Hold for real Caps Lock"),
                        isOn: model.binding(
                            { AppPreferences.isHoldForCapsLockEnabled },
                            { enabled in
                                AppPreferences.isHoldForCapsLockEnabled = enabled
                                if enabled, !HoldForCapsMonitor.hasPermission {
                                    HoldForCapsMonitor.requestPermission()
                                }
                            }))
                    .disabled(!AppPreferences.isRemapEnabled)
                    Text(L(
                        "Hold the key for about half a second to toggle actual Caps "
                            + "Lock — uppercase, keyboard LED and all, just like the key "
                            + "used to. Quick taps keep switching the instant you press, "
                            + "exactly as before. A hold switches at first too, then hops "
                            + "back to the language the press started on as Caps Lock "
                            + "engages — a brief flicker of the input menu is the only "
                            + "trace."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if AppPreferences.isHoldForCapsLockEnabled,
                    !HoldForCapsMonitor.hasPermission
                {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L(
                            "Watching for the hold needs the Input Monitoring "
                                + "permission — the same one the lone-tap switches below "
                                + "use. Until it's granted, switching keeps working as "
                                + "usual and holding does nothing."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Button(L("Open Privacy & Security Settings…")) {
                            openSettingsURL(
                                "com.apple.preference.security?Privacy_ListenEvent")
                        }
                    }
                }
            } header: {
                Text(L("Caps Lock"))
            } footer: {
                Text(L(
                    "The remap lives in macOS's HID system — instant, and no process "
                        + "touches your keystrokes. Turning it off, or quitting Keystone, "
                        + "restores stock Caps Lock immediately."))
            }

            Section {
                Button(L("Open Keyboard Settings…")) {
                    openSettingsURL("com.apple.Keyboard-Settings.extension")
                }
            } header: {
                Text(L("Input source shortcut"))
            } footer: {
                Text(L(
                    "For delay-free input switching, bind the shortcut to the same key: "
                        + "System Settings › Keyboard › Keyboard Shortcuts… › Input "
                        + "Sources › “Select next source in Input menu”, then press "
                        + "Caps Lock to record it."))
            }

            Section {
                ForEach(AppPreferences.TapKey.allCases, id: \.self) { key in
                    Picker(key.title, selection: tapBinding(for: key)) {
                        Text(L("Off")).tag("off")
                        Text(L("Next input source")).tag(AppPreferences.TapAction.toggle.stored)
                        Divider()
                        ForEach(model.enabledSources, id: \.id) { source in
                            Text(source.name)
                                .tag(AppPreferences.TapAction.select(sourceID: source.id).stored)
                        }
                        /* A mapping to a source that's no longer enabled
                           stays visible (and inert) instead of silently
                           vanishing. */
                        if case .select(let sourceID) = AppPreferences.tapActions[key],
                            !model.enabledSources.contains(where: { $0.id == sourceID })
                        {
                            Text(L("%@ (not enabled)", sourceID))
                                .tag(AppPreferences.TapAction.select(sourceID: sourceID).stored)
                        }
                    }
                }

                if !AppPreferences.tapActions.isEmpty, !CommandTapMonitor.hasPermission {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L(
                            "Input Monitoring isn't granted yet — allow Keystone under "
                                + "Privacy & Security › Input Monitoring. The system prompt "
                                + "appears only on the first ask."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Button(L("Open Privacy & Security Settings…")) {
                            openSettingsURL("com.apple.preference.security?Privacy_ListenEvent")
                        }
                    }
                }
            } header: {
                Text(L("Switch input source when tapped alone"))
            } footer: {
                Text(L(
                    "A modifier pressed and released with nothing else in between "
                        + "switches the input source — to the next one, or to the one you "
                        + "pick per key; every shortcut using it keeps working. Watching "
                        + "for that lone tap is the one Keystone feature that observes "
                        + "keys, so it needs the Input Monitoring permission."))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshSources()
        }
    }

    /* Picker selection rides the stored string form: "off", "toggle", or
       "select:<id>" — Hashable for free, one source of truth. */
    private func tapBinding(for key: AppPreferences.TapKey) -> Binding<String> {
        model.binding(
            { AppPreferences.tapActions[key]?.stored ?? "off" },
            { stored in
                AppPreferences.setTapAction(
                    AppPreferences.TapAction(stored: stored), for: key)
                if !AppPreferences.tapActions.isEmpty, !CommandTapMonitor.hasPermission {
                    CommandTapMonitor.requestPermission()
                }
            })
    }

    private func openSettingsURL(_ suffix: String) {
        guard let url = URL(string: "x-apple.systempreferences:" + suffix) else { return }
        NSWorkspace.shared.open(url)
    }
}
