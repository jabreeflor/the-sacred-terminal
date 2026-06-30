# The Sacred Terminal — native macOS app

A native macOS terminal workspace organized around **projects and agents**, modeled on
[cmux](https://github.com/manaflow-ai/cmux) and built **on top of Ghostty**.

## How cmux does it (and how this mirrors it)

cmux is a native macOS app (Swift + AppKit) that **embeds `libghostty`** for terminal rendering —
"the same way apps use WebKit for web views." The key consequence, which shapes this codebase:

> **libghostty owns each terminal surface's PTY *and* its GPU (Metal) rendering.**
> You don't write a pseudo-terminal layer or a cell renderer — you create a *surface*, point it at a
> **command (the agent CLI), a working directory, and env**, host it in an `NSView`, and forward
> keyboard/mouse events. Themes/fonts/colors come from the user's `~/.config/ghostty/config`.

So this app is split the same way cmux is:

| Concern | Owned by |
|---|---|
| Terminal emulation, PTY, GPU rendering | **libghostty** (`GhosttyKit.xcframework`) |
| Projects → agent-bound sessions, rail, splits, settings, menu-bar, browser, socket API | **this app** (Swift + AppKit) |

Source map:

```
Sources/SacredTerminal/
  main.swift, AppDelegate.swift          app bootstrap
  Ghostty/GhosttyBridge.swift            the ONLY seam to ghostty.h (App + Surface)
  Ghostty/SurfaceView.swift              NSView hosting a surface; input forwarding; Metal draw loop
  Models/                                Agent roster (+YOLO), Status/statusMeta, Project/Session/Pane
  State/AppState.swift                   workspace store + actions (persisted as AppSessionSnapshot)
  Views/                                 RailViewController, WorkspaceViewController (tabs+splits),
                                         TitlebarController, AgentPickerController
  Settings/SettingsWindowController.swift
  MenuBar/StatusItemController.swift     the "always running" NSStatusItem pulse + roster
  Browser/BrowserPanelController.swift   integrated WKWebView pane
  Socket/SocketServer.swift              Unix-socket control API (à la cmux's TerminalController)
Sources/sacred-cli/                      the `sacred` CLI that drives a running app over the socket
```

## Build (on a Mac)

This is a Swift Package; libghostty must be vendored first (mirrors cmux's Ghostty submodule):

```bash
cd macos/SacredTerminal

# 1. Vendor Ghostty and build GhosttyKit.xcframework (needs Zig + Xcode CLT).
#    Use cmux's Ghostty fork — it carries the embedding API and stays buildable;
#    upstream ghostty-org/ghostty@main fights the vendored Highway C++ build.
git submodule add https://github.com/manaflow-ai/ghostty vendor/ghostty
git submodule update --init --recursive
./scripts/build-ghostty.sh

# 2. Build / run
swift build
swift run SacredTerminal           # or: ./scripts/package-app.sh && open .build/SacredTerminal.app
```

Open `Package.swift` in Xcode for a normal edit/run/debug/archive flow.

## Notes

- **libghostty's embedding API is pre-1.0.** Every raw `ghostty_*` C call lives in
  `Ghostty/GhosttyBridge.swift`; if you vendor a different GhosttyKit build, reconcile field/function
  names there only — the rest of the app talks to the Swift `GhosttyApp`/`GhosttySurface` types.
- Opening a session whose agent CLI (`claude`, `codex`, …) is on `PATH` launches the real CLI in the
  surface; otherwise it falls back to your shell.
- State persists to `~/Library/Application Support/SacredTerminal/session.json`; the control socket is
  `…/SacredTerminal/control.sock`.
