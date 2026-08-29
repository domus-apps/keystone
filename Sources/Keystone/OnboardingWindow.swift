import AppKit

/* First-run onboarding: what Keystone does and the one manual step it
   cannot do for the user — binding the input-source shortcut in System
   Settings. No permission gate: hidutil needs no TCC grant. The window has
   no close button; the only way out is the Start button, and completion is
   persisted only at that click, so quitting mid-onboarding brings the
   onboarding back on the next launch. */
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onComplete: () -> Void

    private lazy var startButton = NSButton(
        title: "Start Using Keystone", target: self, action: #selector(start))

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        /* No .closable: the traffic-light close button never appears. */
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /* Closing only via start(). */
    func windowShouldClose(_ sender: NSWindow) -> Bool { false }

    // MARK: - Content

    private func makeContent() -> NSView {
        let title = NSTextField(labelWithString: "Welcome to Keystone")
        title.font = .systemFont(ofSize: 30, weight: .bold)

        let intro = NSTextField(
            wrappingLabelWithString:
                "Keystone turns Caps Lock into an instant input-source switch. "
                + "It reroutes Caps Lock to a spare key (F19) inside macOS itself — "
                + "no driver, no keystroke interception, and none of Caps Lock's "
                + "built-in delay.")
        intro.font = .systemFont(ofSize: 14)
        intro.textColor = .secondaryLabelColor
        intro.alignment = .center
        intro.preferredMaxLayoutWidth = 470

        let illustration = OnboardingIllustrationView()
        illustration.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            illustration.widthAnchor.constraint(equalToConstant: 480),
            illustration.heightAnchor.constraint(equalToConstant: 150),
        ])

        let step = NSTextField(
            wrappingLabelWithString:
                "One step to finish in System Settings › Keyboard › Keyboard "
                + "Shortcuts… › Input Sources: set “Select next source in Input "
                + "menu” by pressing Caps Lock — it already types F19.")
        step.font = .systemFont(ofSize: 13)
        step.textColor = .secondaryLabelColor
        step.alignment = .center
        step.preferredMaxLayoutWidth = 470

        let openButton = NSButton(
            title: "Open Keyboard Settings…", target: self,
            action: #selector(openKeyboardSettings))

        startButton.bezelStyle = .rounded
        startButton.controlSize = .large
        startButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, intro, illustration, step, openButton, startButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(10, after: title)
        stack.setCustomSpacing(22, after: intro)
        stack.setCustomSpacing(10, after: step)
        stack.setCustomSpacing(24, after: openButton)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 44),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: container.bottomAnchor, constant: -32),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
        ])
        return container
    }

    @objc private func openKeyboardSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func start() {
        window?.delegate = nil
        onComplete()
        close()
    }
}

/* A drawn diagram of the trick: the Caps Lock keycap flowing into F19,
   flowing into the input-source switch. Drawn (not a bundled image) so it
   stays crisp at any backing scale and needs no resource plumbing. */
private final class OnboardingIllustrationView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let canvas = bounds

        // Backdrop: deep fired-brick brown, the keystone's material
        let backdrop = NSBezierPath(roundedRect: canvas, xRadius: 12, yRadius: 12)
        NSGradient(
            starting: NSColor(srgbRed: 0.19, green: 0.08, blue: 0.04, alpha: 1),
            ending: NSColor(srgbRed: 0.09, green: 0.03, blue: 0.01, alpha: 1)
        )?.draw(in: backdrop, angle: -90)

        func keycap(_ label: String, symbol: String?, center: NSPoint, size: NSSize)
            -> NSRect
        {
            let rect = NSRect(
                x: center.x - size.width / 2, y: center.y - size.height / 2,
                width: size.width, height: size.height)
            let cap = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
            NSColor.white.withAlphaComponent(0.14).setFill()
            cap.fill()
            NSColor.white.withAlphaComponent(0.25).setStroke()
            cap.lineWidth = 1
            cap.stroke()

            var text = label
            if let symbol { text = "\(symbol)  \(label)" }
            let attributed = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                ])
            let textSize = attributed.size()
            attributed.draw(
                at: NSPoint(
                    x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
            return rect
        }

        func arrow(from: NSPoint, to: NSPoint) {
            let path = NSBezierPath()
            path.move(to: from)
            path.line(to: to)
            NSColor.white.withAlphaComponent(0.4).setStroke()
            path.lineWidth = 1.5
            path.stroke()
            let head = NSBezierPath()
            head.move(to: NSPoint(x: to.x - 6, y: to.y + 4))
            head.line(to: to)
            head.line(to: NSPoint(x: to.x - 6, y: to.y - 4))
            head.lineWidth = 1.5
            head.stroke()
        }

        let midY = canvas.midY
        let caps = keycap(
            "caps lock", symbol: "⇪",
            center: NSPoint(x: canvas.minX + 88, y: midY),
            size: NSSize(width: 120, height: 44))
        let f19 = keycap(
            "F19", symbol: nil,
            center: NSPoint(x: canvas.midX + 10, y: midY),
            size: NSSize(width: 64, height: 44))

        // The input-source pill: 한 ↔ A
        let pillRect = NSRect(x: canvas.maxX - 130, y: midY - 22, width: 96, height: 44)
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: 22, yRadius: 22)
        /* The brand terracotta (make-assets.swift), not systemOrange. */
        NSColor(srgbRed: 0.85, green: 0.34, blue: 0.13, alpha: 0.95).setFill()
        pill.fill()
        let swap = NSAttributedString(
            string: "한 ⇄ A",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.white,
            ])
        let swapSize = swap.size()
        swap.draw(
            at: NSPoint(
                x: pillRect.midX - swapSize.width / 2, y: pillRect.midY - swapSize.height / 2))

        arrow(
            from: NSPoint(x: caps.maxX + 8, y: midY),
            to: NSPoint(x: f19.minX - 8, y: midY))
        arrow(
            from: NSPoint(x: f19.maxX + 8, y: midY),
            to: NSPoint(x: pillRect.minX - 8, y: midY))

        // Caption under the flow
        let caption = NSAttributedString(
            string: "rerouted in macOS · zero delay",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.white.withAlphaComponent(0.45),
            ])
        let captionSize = caption.size()
        caption.draw(
            at: NSPoint(x: canvas.midX - captionSize.width / 2, y: canvas.minY + 14))
    }
}
