//  MenuBarRoster.swift
//  The custom content shown inside the menu-bar item's NSPopover (spec §11),
//  matching docs/mock-design/menu-bar.html: a glass dropdown of two-line rows —
//  per-status lead glyph (animated ring spinner while .working, a doc tile for the
//  "needs your input" row, a small status dot otherwise), title + "project · status"
//  sub, and a trailing agent brand icon (or the blue notify dot for .waiting). The
//  popover itself supplies the blurred material, arrow (≈ the mock caret) and rounded
//  corners; this view just lays out the rows on a transparent background.

import AppKit

final class MenuBarRosterViewController: NSViewController {

    private let sessions: [(project: Project, session: Session)]
    private let activeID: String?
    private let onPick: (String) -> Void
    private let onQuit: () -> Void

    /// Mock `.menu` is 440px wide.
    private static let panelWidth: CGFloat = 440
    private static let pad: CGFloat = 7

    init(sessions: [(project: Project, session: Session)],
         activeID: String?,
         onPick: @escaping (String) -> Void,
         onQuit: @escaping () -> Void) {
        self.sessions = sessions
        self.activeID = activeID
        self.onPick = onPick
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.panelWidth),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.pad),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.pad),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Self.pad),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Self.pad),
        ])

        func add(_ row: NSView) {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        if sessions.isEmpty {
            add(MenuBarActionRow(title: "No sessions running", subdued: true, trailing: nil, action: nil))
        } else {
            // Mock order: .working first, then a separator, then the "needs your input"
            // (.waiting) rows at the bottom (the ordering is decided by the caller).
            var insertedNeedsYouSeparator = false
            for (project, session) in sessions {
                if session.status == .waiting, !insertedNeedsYouSeparator {
                    add(MenuBarSeparator())
                    insertedNeedsYouSeparator = true
                }
                let id = session.id
                add(MenuBarSessionRow(project: project, session: session,
                                      isActive: session.id == activeID) { [onPick] in onPick(id) })
            }
        }

        // Functional footer (not in the marketing mock, but the menu-bar item is the
        // app's only affordance once the window is closed): quit.
        add(MenuBarSeparator())
        add(MenuBarActionRow(title: "Quit The Sacred Terminal", subdued: true,
                             trailing: "⌘Q") { [onQuit] in onQuit() })
    }
}

// MARK: - Session row (mock `.row`)

private final class MenuBarSessionRow: NSView {
    private let onPick: () -> Void
    private var tracking: NSTrackingArea?
    private let isActive: Bool

    private static let hoverBg  = NSColor.white.withAlphaComponent(0.05)   // mock .row:hover
    private static let activeBg = NSColor.white.withAlphaComponent(0.07)   // mock .row.active

    init(project: Project, session: Session, isActive: Bool, onPick: @escaping () -> Void) {
        self.onPick = onPick
        self.isActive = isActive
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = (isActive ? Self.activeBg : NSColor.clear).cgColor

        // Lead glyph — 18px slot (mock `.lead`).
        let leadSlot = NSView()
        leadSlot.translatesAutoresizingMaskIntoConstraints = false
        let glyph = MenuBarGlyphs.lead(for: session.status)
        leadSlot.addSubview(glyph)

        // Body — title + sub (mock `.body`).
        let meta = statusMeta(session.status)
        let task = session.task.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleText = task.isEmpty ? Agents.def(session.agent).name : task

        let title = NSTextField(labelWithString: titleText)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = Theme.hex("#f1f0f5")
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Working rows show just the project (mock); others append the status label.
        let subText = session.status == .working
            ? project.name
            : "\(project.name) · \(meta.label)"
        let sub = NSTextField(labelWithString: subText)
        sub.translatesAutoresizingMaskIntoConstraints = false
        sub.font = .systemFont(ofSize: 12)
        sub.textColor = Theme.textFaint
        sub.lineBreakMode = .byTruncatingTail
        sub.cell?.usesSingleLineMode = true
        sub.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let body = NSStackView(views: [title, sub])
        body.translatesAutoresizingMaskIntoConstraints = false
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 2

        // Trailing identity — brand icon, or the notify dot for the waiting row.
        let identSlot = NSView()
        identSlot.translatesAutoresizingMaskIntoConstraints = false
        let ident = MenuBarGlyphs.ident(for: session)
        identSlot.addSubview(ident)

        addSubview(leadSlot)
        addSubview(body)
        addSubview(identSlot)

        NSLayoutConstraint.activate([
            leadSlot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            leadSlot.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadSlot.widthAnchor.constraint(equalToConstant: 18),
            leadSlot.heightAnchor.constraint(equalToConstant: 18),
            glyph.centerXAnchor.constraint(equalTo: leadSlot.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: leadSlot.centerYAnchor),

            body.leadingAnchor.constraint(equalTo: leadSlot.trailingAnchor, constant: 13),
            body.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),

            identSlot.leadingAnchor.constraint(greaterThanOrEqualTo: body.trailingAnchor, constant: 10),
            identSlot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            identSlot.centerYAnchor.constraint(equalTo: centerYAnchor),
            identSlot.widthAnchor.constraint(equalToConstant: 22),
            identSlot.heightAnchor.constraint(equalToConstant: 22),
            ident.centerXAnchor.constraint(equalTo: identSlot.centerXAnchor),
            ident.centerYAnchor.constraint(equalTo: identSlot.centerYAnchor),
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(fire)))
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { onPick() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let a = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .assumeInside],
                               owner: self, userInfo: nil)
        addTrackingArea(a); tracking = a
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = Self.hoverBg.cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = (isActive ? Self.activeBg : NSColor.clear).cgColor
    }
}

// MARK: - Action / message row (empty state, quit)

private final class MenuBarActionRow: NSView {
    private let action: (() -> Void)?
    private var tracking: NSTrackingArea?

    init(title: String, subdued: Bool, trailing: String?, action: (() -> Void)?) {
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10

        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = subdued ? Theme.textDim : Theme.text

        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        if let trailing {
            let key = NSTextField(labelWithString: trailing)
            key.translatesAutoresizingMaskIntoConstraints = false
            key.font = .systemFont(ofSize: 12)
            key.textColor = Theme.textFaint
            addSubview(key)
            NSLayoutConstraint.activate([
                key.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
                key.centerYAnchor.constraint(equalTo: centerYAnchor),
                key.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 10),
            ])
        }

        if action != nil {
            addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(fire)))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { action?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard action != nil else { return }
        if let tracking { removeTrackingArea(tracking) }
        let a = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .assumeInside],
                               owner: self, userInfo: nil)
        addTrackingArea(a); tracking = a
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

// MARK: - Separator (mock `.sep`: 1px line, 6px vertical / 10px horizontal margin)

private final class MenuBarSeparator: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        addSubview(line)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 13),
            line.heightAnchor.constraint(equalToConstant: 1),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Glyph factory

private enum MenuBarGlyphs {

    /// Lead glyph (mock `.lead`): a spinning ring for .working, a doc tile for the
    /// "needs your input" row, and a small filled status dot for .done / .idle.
    static func lead(for status: Status) -> NSView {
        switch status {
        case .working: return RingSpinnerView(color: statusMeta(.working).color, diameter: 14)
        case .waiting: return docTile()
        case .done, .idle: return dot(color: statusMeta(status).color, diameter: 8)
        }
    }

    /// Trailing identity (mock `.ident`): the blue notify dot for .waiting, otherwise
    /// the agent's brand icon (full colour, as in the agent picker).
    static func ident(for session: Session) -> NSView {
        if session.status == .waiting {
            return dot(color: Theme.hex("#2f6fed"), diameter: 8)   // mock --notify
        }
        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        // Some brand SVGs declare `width="1em"` / gradient defs, so NSImage resolves an
        // inconsistent intrinsic size (gemini rasterizes tiny). Pin a square size so
        // every brand mark fills its slot uniformly.
        if let img = Theme.agentImage(session.agent) {
            img.size = NSSize(width: 16, height: 16)
            iv.image = img
        }
        iv.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
        ])
        return iv
    }

    private static func dot(color: NSColor, diameter: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.cornerRadius = diameter / 2
        v.layer?.backgroundColor = color.cgColor
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: diameter),
            v.heightAnchor.constraint(equalToConstant: diameter),
        ])
        return v
    }

    /// Mock `.appicon`: an 18px rounded gradient tile with a faint doc glyph.
    private static func docTile() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true

        let grad = CAGradientLayer()
        grad.frame = v.bounds
        grad.colors = [Theme.hex("#3a3a44").cgColor, Theme.hex("#222229").cgColor]
        grad.startPoint = CGPoint(x: 0.15, y: 0)
        grad.endPoint = CGPoint(x: 0.85, y: 1)
        grad.cornerRadius = 5
        grad.borderWidth = 1
        grad.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        v.layer?.addSublayer(grad)

        let doc = NSImageView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        doc.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        doc.contentTintColor = Theme.hex("#b9b9c4")
        v.addSubview(doc)

        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 18),
            v.heightAnchor.constraint(equalToConstant: 18),
            doc.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            doc.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }
}

// MARK: - Ring spinner (mock `.mini`)

/// A thin ring with one coloured arc that rotates — the mock's per-row working
/// spinner. Layer-drawn so it animates cheaply while the popover is open.
private final class RingSpinnerView: NSView {
    private let diameter: CGFloat

    init(color: NSColor, diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let lw: CGFloat = 2
        let path = CGPath(ellipseIn: bounds.insetBy(dx: lw / 2, dy: lw / 2), transform: nil)

        let track = CAShapeLayer()
        track.frame = bounds
        track.path = path
        track.fillColor = NSColor.clear.cgColor
        track.strokeColor = NSColor.white.withAlphaComponent(0.16).cgColor
        track.lineWidth = lw

        let arc = CAShapeLayer()
        arc.frame = bounds
        arc.path = path
        arc.fillColor = NSColor.clear.cgColor
        arc.strokeColor = color.cgColor
        arc.lineWidth = lw
        arc.lineCap = .round
        arc.strokeStart = 0
        arc.strokeEnd = 0.3

        layer?.addSublayer(track)
        layer?.addSublayer(arc)

        let rot = CABasicAnimation(keyPath: "transform.rotation.z")
        rot.fromValue = 0
        rot.toValue = -Double.pi * 2
        rot.duration = 1.0
        rot.repeatCount = .infinity
        arc.add(rot, forKey: "spin")

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: diameter, height: diameter) }
}
