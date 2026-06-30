//  GhosttyBridge.swift
//  The single seam between Swift and libghostty's C embedding API (ghostty.h),
//  exposed by the vendored GhosttyKit.xcframework. This mirrors how Ghostty's own
//  macOS app (and cmux) embed libghostty: libghostty owns each surface's PTY and
//  its GPU (Metal) rendering — we only create surfaces, hand them an NSView + a
//  command + cwd, and forward input events.
//
//  NOTE: libghostty's embedding API is pre-1.0 and evolving. The C calls below
//  track Ghostty's include/ghostty.h as used by macos/Sources/Ghostty. If you
//  vendor a different GhosttyKit build, reconcile field/function names HERE only —
//  the rest of the app talks to the Swift `GhosttyApp` / `GhosttySurface` types.

import AppKit
import GhosttyKit

/// Process-wide libghostty handle. One app, many surfaces (one surface per pane).
final class GhosttyApp {
    static let shared = GhosttyApp()

    let app: ghostty_app_t
    let config: ghostty_config_t

    private init() {
        // 1. Initialize libghostty once for the process.
        if ghostty_init(0, nil) != 0 {
            fatalError("ghostty_init failed")
        }

        // 2. Load configuration. Default files include ~/.config/ghostty/config,
        //    so themes/fonts/colors come straight from the user's Ghostty setup
        //    (spec §9; same as cmux).
        config = ghostty_config_new()
        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)

        // 3. Runtime config wires libghostty's callbacks back into AppKit.
        var runtime = ghostty_runtime_config_s()
        runtime.userdata = nil
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { _ in
            // libghostty wants a tick on the main thread.
            DispatchQueue.main.async { ghostty_app_tick(GhosttyApp.shared.app) }
        }
        // action_cb returns bool ("did you handle this action?"); read_clipboard_cb
        // returns bool ("is clipboard data available?"). We don't handle either yet,
        // so report false. Signatures (arity + return) must match ghostty.h exactly.
        runtime.action_cb = { _, _, _ in false }            // (app, target, action) -> bool
        runtime.read_clipboard_cb = { _, _, _ in false }    // (userdata, clipboard, state) -> bool
        runtime.write_clipboard_cb = { _, _, _, _, _ in }   // (userdata, clipboard, content, len, confirm)
        runtime.close_surface_cb = { _, _ in }              // (userdata, processAlive)

        guard let created = ghostty_app_new(&runtime, config) else {
            fatalError("ghostty_app_new failed")
        }
        app = created
    }

    /// Drive libghostty's event loop (call from a timer / display link).
    /// ghostty_app_tick returns void in the embedding API.
    func tick() { ghostty_app_tick(app) }
}

/// One Ghostty surface == one terminal pane. libghostty runs the command in a
/// real PTY inside this surface and renders it with Metal into the hosting NSView.
final class GhosttySurface {
    private(set) var surface: ghostty_surface_t?

    /// Create a surface hosted in `view`, running `argv` in `directory`.
    init(view: NSView, argv: [String], directory: String, env: [String: String] = [:]) {
        var cfg = ghostty_surface_config_new()

        // Host the surface in our NSView (libghostty attaches a Metal layer).
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(view).toOpaque()
        ))
        // scale_factor is a C `double`; backingScaleFactor is CGFloat, and the
        // implicit CGFloat→Double bridge doesn't fire through `??`, so convert.
        cfg.scale_factor = Double(view.window?.backingScaleFactor ?? 2.0)

        // The command libghostty spawns in the PTY (the agent CLI or a shell),
        // and the working directory (the project's path).
        let command = argv.joined(separator: " ")
        directory.withCString { dir in
            cfg.working_directory = dir
            command.withCString { cmd in
                cfg.command = cmd
                surface = ghostty_surface_new(GhosttyApp.shared.app, &cfg)
            }
        }
    }

    deinit { free() }

    func free() {
        if let s = surface { ghostty_surface_free(s); surface = nil }
    }

    func setContentScale(_ scale: CGFloat) {
        guard let s = surface else { return }
        ghostty_surface_set_content_scale(s, scale, scale)
    }

    /// Size in *pixels* (points * backingScaleFactor).
    func setSize(width: UInt32, height: UInt32) {
        guard let s = surface else { return }
        ghostty_surface_set_size(s, width, height)
    }

    func setFocus(_ focused: Bool) {
        guard let s = surface else { return }
        ghostty_surface_set_focus(s, focused)
    }

    func draw() {
        guard let s = surface else { return }
        ghostty_surface_draw(s)
    }

    /// Forward a key event. libghostty encodes it (Kitty protocol, etc.) and
    /// writes the bytes to the PTY itself.
    func sendKey(_ event: ghostty_input_key_s) {
        guard let s = surface else { return }
        ghostty_surface_key(s, event)
    }

    /// Inject text directly into the PTY (used by the message bar, spec §6).
    func sendText(_ text: String) {
        guard let s = surface else { return }
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { buf in
            ghostty_surface_text(s, buf.baseAddress, UInt(buf.count))
        }
    }

    func mouseButton(action: ghostty_input_mouse_state_e, button: ghostty_input_mouse_button_e, mods: ghostty_input_mods_e) {
        guard let s = surface else { return }
        ghostty_surface_mouse_button(s, action, button, mods)
    }

    func mousePos(x: Double, y: Double, mods: ghostty_input_mods_e) {
        guard let s = surface else { return }
        ghostty_surface_mouse_pos(s, x, y, mods)
    }

    func mouseScroll(x: Double, y: Double, mods: ghostty_input_scroll_mods_t) {
        guard let s = surface else { return }
        ghostty_surface_mouse_scroll(s, x, y, mods)
    }
}
