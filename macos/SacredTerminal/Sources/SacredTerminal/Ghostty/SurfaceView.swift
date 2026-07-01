//  SurfaceView.swift
//  An NSView that hosts a single libghostty surface (one terminal pane).
//  libghostty attaches its own Metal layer and renders into this view; we feed it
//  size/scale changes and forward keyboard/mouse events. Modeled on Ghostty's
//  macos/Sources/Ghostty/SurfaceView_AppKit.swift.

import AppKit
import GhosttyKit

final class SurfaceView: NSView {
    private var ghostty: GhosttySurface?
    /// Tracks what we've told libghostty — avoids redundant set_focus calls.
    private var ghosttyFocused = false
    /// Accumulates composed text while `interpretKeyEvents` runs inside `keyDown`.
    private var keyTextAccumulator: [String]?

    let paneID: String
    let sessionID: String
    private let argv: [String]
    private let directory: String

    /// Called when the user clicks this pane (drives active-pane state).
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
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.ghostty == nil else { return }
            self.ghostty = GhosttySurface(view: self, argv: self.argv, directory: self.directory)
            self.ghostty?.setContentScale(self.window?.backingScaleFactor ?? 2.0)
            self.updateSurfaceSize()
            self.syncGhosttyFocus()
            self.ghostty?.refresh()
        }
    }

    override func removeFromSuperview() {
        ghostty?.free()
        ghostty = nil
        super.removeFromSuperview()
    }

    func send(text: String) { ghostty?.sendText(text) }

    func focusSurface() {
        window?.makeFirstResponder(self)
        syncGhosttyFocus()
    }

    func focusFromUserInteraction() {
        focusSurface()
        onFocus?(paneID)
    }

    func syncGhosttyFocus() {
        let shouldFocus = (window?.isKeyWindow ?? false) && (window?.firstResponder === self)
        guard ghostty != nil, ghosttyFocused != shouldFocus else { return }
        ghosttyFocused = shouldFocus
        ghostty?.setFocus(shouldFocus)
    }

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

    // MARK: - Focus

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { syncGhosttyFocus() }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { syncGhosttyFocus() }
        return ok
    }

    // MARK: - Keyboard (Ghostty SurfaceView_AppKit pattern)

    override func keyDown(with event: NSEvent) {
        guard let ghostty else {
            interpretKeyEvents([event])
            return
        }

        let translationMods = GhosttyInput.translatedModifierFlags(for: event, surface: ghostty)
        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        interpretKeyEvents([translationEvent])

        if let list = keyTextAccumulator, !list.isEmpty {
            for text in list {
                _ = keyAction(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            _ = keyAction(action, event: event, translationEvent: translationEvent,
                          text: translationEvent.ghosttyCharacters)
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = keyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        _ = keyAction(GHOSTTY_ACTION_PRESS, event: event)
    }

    override func doCommand(by selector: Selector) {
        // Swallow unhandled edit commands so AppKit doesn't beep; bindings are
        // encoded through keyDown after interpretKeyEvents.
    }

    @discardableResult
    private func keyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let ghostty else { return false }
        var key = event.ghosttyKeyEvent(action, translationMods: translationEvent?.modifierFlags)
        key.composing = composing
        if let text, !text.isEmpty, let codepoint = text.utf8.first, codepoint >= 0x20 {
            return text.withCString { ptr in
                key.text = ptr
                return ghostty.sendKey(key)
            }
        }
        key.text = nil
        return ghostty.sendKey(key)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        syncGhosttyFocus()
        onFocus?(paneID)
        mouseButton(event, .left, down: true)
    }

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
        ghostty_input_scroll_mods_t(precise ? 1 : 0)
    }
}

// MARK: - NSTextInputClient (minimal stubs for interpretKeyEvents / IME)

extension SurfaceView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil else { return }
        let chars: String
        switch string {
        case let v as NSAttributedString: chars = v.string
        case let v as String: chars = v
        default: return
        }
        if var acc = keyTextAccumulator {
            acc.append(chars)
            keyTextAccumulator = acc
            return
        }
        ghostty?.sendText(chars)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func attributedSubstring(forProposedRange range: NSRange,
                             actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func firstRect(forCharacterRange range: NSRange,
                   actualRange: NSRangePointer?) -> NSRect { .zero }
    func characterIndex(for point: NSPoint) -> Int { 0 }
}
