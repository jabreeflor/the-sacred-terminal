//  StatusItemController.swift
//  The "always running" presence in the system menu bar (spec §11).
//
//  An NSStatusItem whose button glyph reflects the aggregate state of every
//  session: it spins while ANY session is .working and wears an attention dot
//  while ANY session is .waiting. Clicking it drops a custom glass roster
//  (NSPopover hosting `MenuBarRosterViewController`, matching the mock at
//  docs/mock-design/menu-bar.html) — one row per session, .working first, then a
//  separator, then the ones that need you (.waiting). Selecting a row posts
//  `.sacredFocusSession` (snap-back) so the main window re-focuses that session.

import AppKit

final class StatusItemController: NSObject, NSPopoverDelegate {

    private let statusItem: NSStatusItem
    private var observer: NSObjectProtocol?

    /// The custom glass dropdown. Content is rebuilt fresh on each open so it always
    /// reflects current state. `.transient` dismisses on any outside interaction.
    private lazy var popover: NSPopover = {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.appearance = NSAppearance(named: .darkAqua)
        p.delegate = self
        return p
    }()

    /// Set briefly when the popover closes so the same click that dismissed it (when
    /// it lands on the status button) doesn't immediately reopen it.
    private var popoverJustClosed = false

    /// Drives the spin animation while any session is .working.
    private var spinTimer: Timer?
    private var spinAngle: CGFloat = 0

    /// Whether the most recent recompute found a .waiting session.
    private var hasWaiting = false
    /// Whether the most recent recompute found a .working session.
    private var hasWorking = false

    // MARK: - Lifecycle

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = baseGlyph()
            button.imagePosition = .imageOnly
            button.toolTip = "The Sacred Terminal"
            button.target = self
            button.action = #selector(togglePopover)
        }

        observer = NotificationCenter.default.addObserver(
            forName: .sacredStateChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.recompute() }

        recompute()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        spinTimer?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Aggregate state -> button treatment

    /// Recompute the aggregate pulse from every session and update the button.
    private func recompute() {
        let statuses = AppState.shared.allSessions.map { $0.session.status }
        hasWorking = statuses.contains(.working)
        hasWaiting = statuses.contains(.waiting)

        if hasWorking {
            startSpinning()
        } else {
            stopSpinning()
            statusItem.button?.image = composedGlyph(rotation: 0)
        }

        statusItem.button?.toolTip = tooltip()
    }

    private func tooltip() -> String {
        let working = AppState.shared.allSessions.filter { $0.session.status == .working }.count
        let waiting = AppState.shared.allSessions.filter { $0.session.status == .waiting }.count
        var parts: [String] = []
        if working > 0 { parts.append("\(working) working") }
        if waiting > 0 { parts.append("\(waiting) need\(waiting == 1 ? "s" : "") you") }
        return parts.isEmpty ? "The Sacred Terminal" : "The Sacred Terminal — " + parts.joined(separator: ", ")
    }

    // MARK: - Spin animation

    private func startSpinning() {
        guard spinTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.spinAngle += .pi / 24            // ~ a full turn every ~1.6s
            if self.spinAngle > .pi * 2 { self.spinAngle -= .pi * 2 }
            self.statusItem.button?.image = self.composedGlyph(rotation: self.spinAngle)
        }
        RunLoop.main.add(timer, forMode: .common)
        spinTimer = timer
    }

    private func stopSpinning() {
        spinTimer?.invalidate()
        spinTimer = nil
        spinAngle = 0
    }

    // MARK: - Glyph drawing

    private let glyphSize = NSSize(width: 18, height: 18)

    /// The static idle glyph (a thin terminal-style ring) used before any state arrives.
    private func baseGlyph() -> NSImage {
        composedGlyph(rotation: 0)
    }

    /// Draw the menu-bar glyph: a ring with an open gap (rotated while working) and,
    /// when any session is .waiting, an attention dot in the upper-right corner.
    /// Rendered as a template image so it adapts to light/dark menu bars, except the
    /// waiting dot which is tinted with the .waiting status color.
    private func composedGlyph(rotation: CGFloat) -> NSImage {
        let image = NSImage(size: glyphSize, flipped: false) { [weak self] rect in
            guard let self else { return false }

            let lineWidth: CGFloat = 1.6
            let inset = lineWidth + 1
            let ringRect = rect.insetBy(dx: inset, dy: inset)
            let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
            let radius = min(ringRect.width, ringRect.height) / 2

            // Ring with a gap so rotation reads as motion (a spinner) while working.
            let gap: CGFloat = self.hasWorking ? 70 : 0
            let start = rotation * 180 / .pi
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.appendArc(withCenter: center, radius: radius,
                           startAngle: start + gap / 2,
                           endAngle: start + 360 - gap / 2,
                           clockwise: false)
            NSColor.black.setStroke()   // template: actual color comes from the menu bar
            path.stroke()

            // A small filled core dot keeps the glyph legible at idle.
            if !self.hasWorking {
                let coreR: CGFloat = 1.4
                let core = NSBezierPath(ovalIn: NSRect(x: center.x - coreR, y: center.y - coreR,
                                                       width: coreR * 2, height: coreR * 2))
                NSColor.black.setFill()
                core.fill()
            }

            return true
        }
        image.isTemplate = true

        // The waiting badge is overlaid in color (not template) so it always stands out.
        guard hasWaiting else { return image }

        let badged = NSImage(size: glyphSize, flipped: false) { rect in
            image.draw(in: rect)
            let dotR: CGFloat = 3
            let dotRect = NSRect(x: rect.maxX - dotR * 2 - 0.5,
                                 y: rect.maxY - dotR * 2 - 0.5,
                                 width: dotR * 2, height: dotR * 2)
            Theme.hex("#2f6fed").setFill()   // mock --notify badge
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        badged.isTemplate = false
        return badged
    }

    // MARK: - Popover (rebuilt each time it opens)

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        if popoverJustClosed { return }   // swallow the click that just dismissed it

        popover.contentViewController = MenuBarRosterViewController(
            sessions: orderedSessions(),
            activeID: AppState.shared.activeSessionID,
            onPick: { [weak self] id in
                self?.popover.performClose(nil)
                NotificationCenter.default.post(name: .sacredFocusSession, object: id)
            },
            onQuit: { NSApp.terminate(nil) })

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Make the popover window key so Esc / arrow keys reach it.
        popover.contentViewController?.view.window?.makeKey()
    }

    // NSPopoverDelegate — keep the menu-bar button looking "pressed" while open, and
    // briefly guard against the dismiss-click immediately reopening it.
    func popoverWillShow(_ notification: Notification) {
        statusItem.button?.highlight(true)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
        popoverJustClosed = true
        DispatchQueue.main.async { [weak self] in self?.popoverJustClosed = false }
    }

    /// Sort (mock order): .working first, then .done, .idle, and .waiting LAST so the
    /// "needs your input" rows sit at the bottom below a separator. Stable within a
    /// group by their natural order in the workspace tree.
    private func orderedSessions() -> [(project: Project, session: Session)] {
        func rank(_ s: Status) -> Int {
            switch s {
            case .working: return 0
            case .done:    return 1
            case .idle:    return 2
            case .waiting: return 3
            }
        }
        return AppState.shared.allSessions
            .enumerated()
            .sorted { a, b in
                let ra = rank(a.element.session.status), rb = rank(b.element.session.status)
                if ra != rb { return ra < rb }
                return a.offset < b.offset
            }
            .map { $0.element }
    }
}
