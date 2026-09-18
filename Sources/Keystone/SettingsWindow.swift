import AppKit
import Combine
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
        let window = SettingsWindow(contentViewController: splitViewController)
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
        window.setContentSize(NSSize(width: 640, height: 560))
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

/* macOS 27.2 (26B5086k, measured 2026-09-18): clicking a SwiftUI switch
   Toggle in this window twice leaves the window undraggable by its title bar
   until the app relaunches. `isMovable` still reads true and the app still
   receives the title-bar mouse events; the window server just stops moving
   the window. It is the hosted NSSwitch (SwiftUI's Toggle, or any NSSwitch
   inside an NSHostingView) — a bare AppKit NSSwitch and a checkbox Toggle
   are fine. Re-asserting `isMovable` resyncs whatever the window server
   dropped, and it has to happen before the drag's mouse-down (the server
   decides at that moment; resetting inside the mouse-down is too late), so
   every click in the window ends with a reset. The setter is cheap, and a
   no-op when nothing is wrong. Verified 6/6 against a deterministic repro. */
final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        if event.type == .leftMouseUp, isMovable {
            isMovable = false
            isMovable = true
        }
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
        let target: CGFloat = atRest ? 0 : 1
        /* Only when the value changes. The animator sets the model value at
           once, so a pocket already at the target is skipped. Starting an
           animation on every layout pass dirtied the view for the next
           commit, which laid the sidebar out again, which started another
           animation: a loop that kept each app near 7% CPU for as long as
           it ran, the closed (retained) Settings window included. */
        for subview in scrollView.subviews
        where String(describing: type(of: subview)) == "NSScrollPocket"
            && subview.alphaValue != target {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                subview.animator().alphaValue = target
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
    /* The keycode "Select next source in Input menu" is bound to, if any:
       what tells the native path's section whether the user has done the
       one step in Keyboard Settings. */
    @Published private(set) var nextSourceKeyCode: Int64?

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
        nextSourceKeyCode = SystemHotkeys.nextSourceKeyCode()
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
                    L("Remap Keys"),
                    isOn: model.binding(
                        { AppPreferences.isRemapEnabled },
                        { AppPreferences.isRemapEnabled = $0 }))

                if AppPreferences.needsInputMonitoring || AppPreferences.isHoldForCapsLockEnabled,
                    !SwitchKeyMonitor.hasPermission
                {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L(
                            "Input Monitoring isn't granted yet — allow Keystone under "
                                + "Privacy & Security › Input Monitoring. The system prompt "
                                + "appears only on the first ask. Until then, keys that "
                                + "Keystone switches itself do nothing."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Button(L("Open Privacy & Security Settings…")) {
                            openSettingsURL("com.apple.preference.security?Privacy_ListenEvent")
                        }
                    }
                }
            }

            /* Plain-language guide to the two paths, for people who will
               never read the code comments: what each one is, what it costs,
               and which to start with. Its own section, so it reads as
               advice about the Action pickers below rather than as a
               description of the switch above. */
            Section(L("Choosing an action")) {
                /* Markdown, so the mode name can be bold: the string is a
                   whole paragraph, and the emphasis has to survive
                   translation, so it lives in the string itself. */
                Text(markdown(L(
                    "**System shortcut** lets macOS do the switching. It works everywhere "
                        + "and needs no permission. The other options let Keystone switch "
                        + "instead, which needs Input Monitoring and may not take effect "
                        + "right away in some places. Start with **System shortcut**, and "
                        + "use the others only when you need more.")))
                .foregroundStyle(.secondary)
            }

            ForEach(KeyRemap.Key.allCases, id: \.self) { key in
                keySection(key)
                    .disabled(!AppPreferences.isRemapEnabled)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshSources()
        }
        /* Coming back from System Settings, where both the source list and
           the shortcut are edited. */
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSources()
        }
    }

    /* One section per key: the action, then only the controls that action
       calls for — the trigger choice (modifiers switched by Keystone), the
       destination key (anything rerouted), the Keyboard Settings shortcut
       (native). The footer explains the chosen path in the key's own
       terms. */
    @ViewBuilder
    private func keySection(_ key: KeyRemap.Key) -> some View {
        let binding = AppPreferences.bindings[key]
        /* The system has one "next source" shortcut, so one key holds the
           native path at a time. Rather than letting a second key take it
           away silently, the option is greyed out and names the holder. */
        /* The key, other than this one, that holds the system shortcut. */
        let nativeHolder = AppPreferences.nativeKey.flatMap { $0 == key ? nil : $0 }
        /* "Next input source" opens up only once some OTHER key carries the
           system shortcut: it does the same job less reliably, so everyone
           gets the reliable path first. (A key can't trade its own system
           shortcut for it, since that would leave none.) Jumping to a
           specific source is a different job and is always offered. */
        let nextSourceLocked = nativeHolder == nil
        Section {
            Picker(L("Action"), selection: actionBinding(for: key)) {
                Text(L("Off")).tag("off")
                Divider()
                Text(
                    nativeHolder.map { L("System shortcut (used by %@)", $0.title) }
                        ?? L("System shortcut")
                )
                .tag(AppPreferences.SwitchAction.native.stored)
                .selectionDisabled(nativeHolder != nil)
                Text(L("Next input source"))
                    .tag(AppPreferences.SwitchAction.toggle.stored)
                    .selectionDisabled(nextSourceLocked)
                /* The specific sources under their own heading, so the
                   menu reads as "cycle" versus "jump to this one". */
                Section(L("Switch to input source")) {
                    ForEach(model.enabledSources, id: \.id) { source in
                        Text(source.name)
                            .tag(AppPreferences.SwitchAction.select(sourceID: source.id).stored)
                    }
                    /* A mapping to a source that's no longer enabled stays
                       visible (and inert) instead of silently vanishing. */
                    if case .select(let sourceID) = binding?.action,
                        !model.enabledSources.contains(where: { $0.id == sourceID })
                    {
                        Text(L("%@ (not enabled)", sourceID))
                            .tag(AppPreferences.SwitchAction.select(sourceID: sourceID).stored)
                    }
                }
            }

            if let binding {
                if key.isModifier, binding.usesEventTap {
                    Picker(L("Switches"), selection: triggerBinding(for: key)) {
                        Text(L("On release, keeping shortcuts")).tag("release")
                        Text(L("Instantly, on press")).tag("press")
                    }
                }

                if binding.action == .native {
                    /* Only the native path has a function key: the system
                       shortcut needs a real key to be bound to. */
                    let taken = AppPreferences.takenFunctionKeys(excluding: key)
                    Picker(L("Destination key"), selection: destinationBinding(for: key)) {
                        ForEach(KeyRemap.FunctionKey.allCases.filter { !taken.contains($0) }, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                }

                if binding.action == .native {
                    /* Whether the system shortcut already points at this
                       key's function key; once it does, the button has
                       nothing left to do. */
                    let isBound =
                        binding.destination.map { $0.keyCode == model.nextSourceKeyCode } ?? false
                    VStack(alignment: .leading, spacing: 3) {
                        Button(L("Open Keyboard Settings…")) {
                            openSettingsURL("com.apple.Keyboard-Settings.extension")
                        }
                        .disabled(isBound)
                        /* The one step the button leads to, right where the
                           button is — or the fact that it's done. */
                        Text(
                            isBound
                                ? L("“Select next source in Input menu” is set to %@.", key.title)
                                : L(
                                    "Under Keyboard Shortcuts… › Input Sources, set “Select next "
                                        + "source in Input menu” by pressing %@.",
                                    key.title))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if key == .capsLock {
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
                    .disabled(binding == nil)
                    Text(L(
                        "Hold for about half a second to toggle real Caps Lock, LED and "
                            + "all. A quick tap still switches the input source. Needs the "
                            + "Input Monitoring permission."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(key.title)
        } footer: {
            Text(footer(for: key, binding: binding))
        }
    }

    private func footer(for key: KeyRemap.Key, binding: AppPreferences.KeyBinding?) -> String {
        guard let binding else {
            return L("Stock macOS behavior.")
        }
        let destination = binding.destination?.title ?? ""
        switch (binding.action, binding.trigger) {
        case (.native, _):
            return L(
                "%1$@ acts as %2$@, and macOS does the switching. Works everywhere, "
                    + "including password fields.",
                key.title, destination)
        case (_, .press) where key.isModifier:
            return L(
                "%@ switches the instant it goes down and does nothing else: it is no "
                    + "longer a modifier, so shortcuts that use it stop working, and no "
                    + "other app sees the press. Needs the Input Monitoring permission, and "
                    + "does nothing while secure input is on, such as in password fields.",
                key.title)
        case (_, .press), (_, .remap):
            return L(
                "Keystone switches the instant %@ goes down. The key does nothing else — "
                    + "no Caps Lock, no other app sees the press. Needs the Input Monitoring "
                    + "permission, and does nothing while secure input is on, such as in "
                    + "password fields.",
                key.title)
        case (_, .release):
            return L(
                "%@ pressed and released with nothing else in between switches; every "
                    + "shortcut using it keeps working. Needs the Input Monitoring "
                    + "permission.",
                key.title)
        }
    }

    /* Picker selections ride the stored string forms — Hashable for free,
       one source of truth. A key switched on from Off starts on the safe
       trigger: release for a modifier (its shortcuts survive), and
       setBinding turns that into a rerouting for anything that must be
       rerouted. */
    private func actionBinding(for key: KeyRemap.Key) -> Binding<String> {
        model.binding(
            { AppPreferences.bindings[key]?.action.stored ?? "off" },
            { stored in
                guard let action = AppPreferences.SwitchAction(stored: stored) else {
                    AppPreferences.setBinding(nil, for: key)
                    return
                }
                let trigger = AppPreferences.bindings[key]?.trigger ?? .release
                AppPreferences.setBinding(
                    AppPreferences.KeyBinding(action: action, trigger: trigger), for: key)
                requestPermissionIfNeeded()
            })
    }

    private func triggerBinding(for key: KeyRemap.Key) -> Binding<String> {
        model.binding(
            { AppPreferences.bindings[key]?.trigger == .release ? "release" : "press" },
            { stored in
                guard var binding = AppPreferences.bindings[key] else { return }
                binding.trigger = stored == "release" ? .release : .press
                AppPreferences.setBinding(binding, for: key)
            })
    }

    private func destinationBinding(for key: KeyRemap.Key) -> Binding<KeyRemap.FunctionKey> {
        model.binding(
            { AppPreferences.bindings[key]?.destination ?? .f19 },
            { destination in
                guard var binding = AppPreferences.bindings[key] else { return }
                binding.trigger = .remap(destination)
                AppPreferences.setBinding(binding, for: key)
            })
    }

    private func requestPermissionIfNeeded() {
        if AppPreferences.needsInputMonitoring, !SwitchKeyMonitor.hasPermission {
            SwitchKeyMonitor.requestPermission()
        }
    }

    private func openSettingsURL(_ suffix: String) {
        guard let url = URL(string: "x-apple.systempreferences:" + suffix) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Inline Markdown (bold, italics) for settings copy; falls back to the plain
/// text if the string doesn't parse.
private func markdown(_ string: String) -> AttributedString {
    (try? AttributedString(markdown: string)) ?? AttributedString(string)
}
