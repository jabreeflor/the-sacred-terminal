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
        //    so fonts/keybinds/etc. come from the user's Ghostty setup (spec §9).
        // Use a local handle so the withCString closures don't capture `self`
        // (the stored `config`/`app` members aren't initialized yet).
        let cfg: ghostty_config_t = ghostty_config_new()
        ghostty_config_load_default_files(cfg)
        // Pin the app's design theme — Catppuccin Frappé (spec §9 / the mock) — ONLY
        // when the user hasn't chosen a theme in their own Ghostty config. Loading it
        // unconditionally after the user's files silently overrode their theme, which
        // also contradicted Settings → Appearance ("imported from your Ghostty config").
        // Now Frappé is just the default for users who haven't set one; a user theme
        // wins. (`path` is a diagnostics label; withCString NUL-terminates it.)
        if GhosttyApp.resolvedTheme().isAppDefault {
            let overrides = "theme = catppuccin-frappe"
            overrides.withCString { contents in
                "sacred-terminal-defaults".withCString { path in
                    ghostty_config_load_string(cfg, contents, UInt(overrides.utf8.count), path)
                }
            }
        }
        ghostty_config_finalize(cfg)
        config = cfg

        // 3. Runtime config wires libghostty's callbacks back into AppKit.
        var runtime = ghostty_runtime_config_s()
        runtime.userdata = nil
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { _ in
            DispatchQueue.main.async { ghostty_app_tick(GhosttyApp.shared.app) }
        }
        runtime.action_cb = { _, target, action in
            guard action.tag == GHOSTTY_ACTION_RENDER,
                  target.tag == GHOSTTY_TARGET_SURFACE,
                  let handle = target.target.surface else { return false }
            DispatchQueue.main.async {
                GhosttySurfaceRegistry.shared.draw(handle)
            }
            return false
        }
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

    /// Mirror the host window's key state — libghostty ignores surface keys when
    /// the app isn't focused (Ghostty's BaseTerminalController does the same).
    func setAppFocus(_ focused: Bool) { ghostty_app_set_focus(app, focused) }

    // MARK: - Theme resolution (Settings → Appearance)

    /// The terminal theme actually in effect: the user's Ghostty `theme` if they set
    /// one, otherwise the app's Catppuccin Frappé default. Static + cheap (just reads
    /// the user's config files), so the Settings UI can call it without spinning up
    /// libghostty. `isAppDefault` is true only when we're supplying Frappé ourselves.
    static func resolvedTheme() -> (name: String, isAppDefault: Bool) {
        if let userTheme = userConfiguredTheme() { return (userTheme, false) }
        return ("catppuccin-frappe", true)
    }

    /// Scan the user's Ghostty config file(s) for an uncommented `theme` setting.
    /// Returns its value (e.g. "nord", or "light:…,dark:…") or nil if none is set.
    /// Mirrors Ghostty's default config locations on macOS; not a full parser (it does
    /// not follow `config-file` includes), but it covers themes set in the main file.
    private static func userConfiguredTheme() -> String? {
        let home = NSHomeDirectory()
        var paths: [String] = []
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            paths.append("\(xdg)/ghostty/config")
        }
        paths.append("\(home)/.config/ghostty/config")
        paths.append("\(home)/Library/Application Support/com.mitchellh.ghostty/config")

        for path in paths {
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for rawLine in contents.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard let eq = line.firstIndex(of: "=") else { continue }
                guard line[..<eq].trimmingCharacters(in: .whitespaces) == "theme" else { continue }
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
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

        // The command libghostty spawns in the PTY (the agent CLI or a shell), and the
        // working directory (the project's path). Resolve the executable to an absolute
        // path against the (login-shell) PATH so agent CLIs under nvm / Homebrew /
        // ~/.local/bin are found even when libghostty execs them directly.
        var resolvedArgv = argv
        if let exe = argv.first { resolvedArgv[0] = GhosttySurface.resolveExecutable(exe) }
        let command = resolvedArgv.joined(separator: " ")
        directory.withCString { dir in
            cfg.working_directory = dir
            command.withCString { cmd in
                cfg.command = cmd
                surface = ghostty_surface_new(GhosttyApp.shared.app, &cfg)
                if let s = surface {
                    GhosttySurfaceRegistry.shared.register(s, self)
                }
            }
        }
    }

    deinit { free() }

    /// Resolve a bare command name to an absolute path against the current PATH
    /// (set from the login shell at launch). Returns the input unchanged if it's
    /// already absolute or can't be found (so the failure surfaces in the terminal).
    static func resolveExecutable(_ name: String) -> String {
        guard !name.hasPrefix("/") else { return name }
        guard let pathEnv = getenv("PATH") else { return name }
        let fm = FileManager.default
        for dir in String(cString: pathEnv).split(separator: ":") where !dir.isEmpty {
            let full = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: full) { return full }
        }
        return name
    }

    func free() {
        if let s = surface {
            GhosttySurfaceRegistry.shared.unregister(s)
            ghostty_surface_free(s)
            surface = nil
        }
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

    func refresh() {
        guard let s = surface else { return }
        ghostty_surface_refresh(s)
        draw()
    }

    /// Forward a key event. libghostty encodes it (Kitty protocol, etc.) and
    /// writes the bytes to the PTY itself.
    @discardableResult
    func sendKey(_ event: ghostty_input_key_s) -> Bool {
        guard let s = surface else { return false }
        return ghostty_surface_key(s, event)
    }

    func translateKeyMods(_ mods: ghostty_input_mods_e) -> ghostty_input_mods_e {
        guard let s = surface else { return mods }
        return ghostty_surface_key_translation_mods(s, mods)
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
