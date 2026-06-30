//  SurfaceView.swift
//  An NSView that hosts a single libghostty surface (one terminal pane).
//  libghostty attaches its own Metal layer and renders into this view; we feed it
//  size/scale changes and forward keyboard/mouse events. Modeled on Ghostty's
//  macos/Sources/Ghostty/SurfaceView_AppKit.swift.

import AppKit
import GhosttyKit

final class SurfaceView: NSView {
    private var ghostty: GhosttySurface?
    private var displayLink: CVDisplayLink?

    let paneID: String
    let sessionID: String
    private let argv: [String]
    private let directory: String

    /// Called when this surface gains focus (drives the active-pane state).
    var onFocus: ((String) -> Void)?

    init(sessionID: String, paneID: String, argv: [String], directory: String) {
        self.sessionID = sessionID
        self.paneID = paneID
        self.argv = argv
        self.directory = directory
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    // MARK: - Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, ghostty == nil else { return }
        // Create the surface now that we have a window/backing scale; libghostty
        // spawns the PTY (the agent CLI or shell) and starts rendering.
        ghostty = GhosttySurface(view: self, argv: argv, directory: directory)
        ghostty?.setContentScale(window?.backingScaleFactor ?? 2.0)
        updateSurfaceSize()
        startDisplayLink()
    }

    override func removeFromSuperview() {
        stopDisplayLink()
        ghostty?.free()
        ghostty = nil
        super.removeFromSuperview()
    }

    /// Push raw text into the PTY (message bar, spec §6).
    func send(text: String) { ghostty?.sendText(text) }

    func focusSurface() { window?.makeFirstResponder(self) }

    // MARK: - Sizing

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSurfaceSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2.0
        ghostty?.setContentScale(scale)
        updateSurfaceSize()
    }

    private func updateSurfaceSize() {
        let scale = window?.backingScaleFactor ?? 2.0
        let px = bounds.size
        ghostty?.setSize(width: UInt32(max(1, px.width * scale)),
                         height: UInt32(max(1, px.height * scale)))
    }

    // MARK: - Draw loop (CVDisplayLink -> surface.draw)

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, userInfo) -> CVReturn in
            let view = Unmanaged<SurfaceView>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async { view.ghostty?.draw() }
            return kCVReturnSuccess
        }, ctx)
        CVDisplayLinkStart(link)
        displayLink = link
    }

    private func stopDisplayLink() {
        if let link = displayLink { CVDisplayLinkStop(link) }
        displayLink = nil
    }

    // MARK: - Focus

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        ghostty?.setFocus(true)
        onFocus?(paneID)
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        ghostty?.setFocus(false)
        return super.resignFirstResponder()
    }

    // MARK: - Keyboard (NSEvent -> ghostty_input_key_s)

    override func keyDown(with event: NSEvent) { sendKey(event, action: GHOSTTY_ACTION_PRESS) }
    override func keyUp(with event: NSEvent) { sendKey(event, action: GHOSTTY_ACTION_RELEASE) }
    override func flagsChanged(with event: NSEvent) { sendKey(event, action: GHOSTTY_ACTION_PRESS) }

    private func sendKey(_ event: NSEvent, action: ghostty_input_action_e) {
        var key = ghostty_input_key_s()
        key.action = action
        key.mods = GhosttyInput.mods(from: event.modifierFlags)
        key.keycode = UInt32(event.keyCode)
        let text = event.characters ?? ""
        // libghostty copies the text synchronously during ghostty_surface_key.
        text.withCString { ptr in
            key.text = ptr
            ghostty?.sendKey(key)
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) { focusSurface(); mouseButton(event, .left, down: true) }
    override func mouseUp(with event: NSEvent) { mouseButton(event, .left, down: false) }
    override func rightMouseDown(with event: NSEvent) { mouseButton(event, .right, down: true) }
    override func rightMouseUp(with event: NSEvent) { mouseButton(event, .right, down: false) }

    override func mouseMoved(with event: NSEvent) { mousePos(event) }
    override func mouseDragged(with event: NSEvent) { mousePos(event) }

    override func scrollWheel(with event: NSEvent) {
        ghostty?.mouseScroll(x: Double(event.scrollingDeltaX),
                             y: Double(event.scrollingDeltaY),
                             mods: GhosttyInput.scrollMods(precise: event.hasPreciseScrollingDeltas))
    }

    private enum Btn { case left, right }
    private func mouseButton(_ event: NSEvent, _ btn: Btn, down: Bool) {
        ghostty?.mouseButton(action: down ? GHOSTTY_MOUSE_PRESS : GHOSTTY_MOUSE_RELEASE,
                             button: btn == .left ? GHOSTTY_MOUSE_LEFT : GHOSTTY_MOUSE_RIGHT,
                             mods: GhosttyInput.mods(from: event.modifierFlags))
    }

    private func mousePos(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let scale = window?.backingScaleFactor ?? 2.0
        ghostty?.mousePos(x: Double(p.x * scale),
                          y: Double((bounds.height - p.y) * scale),
                          mods: GhosttyInput.mods(from: event.modifierFlags))
    }
}

/// NSEvent → libghostty input enums. Isolated so the mapping lives in one place.
enum GhosttyInput {
    static func mods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw: UInt32 = 0
        if flags.contains(.shift)   { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option)  { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(raw)
    }

    static func scrollMods(precise: Bool) -> ghostty_input_scroll_mods_t {
        // bit 0 = precise scrolling, per ghostty.h
        ghostty_input_scroll_mods_t(precise ? 1 : 0)
    }
}
