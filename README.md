# the-sacred-terminal

A **native macOS** terminal workspace organized around **projects and agents**, not terminal tabs —
modeled on [cmux](https://github.com/manaflow-ai/cmux) and built **on top of Ghostty**.

cmux-style collapsible rail · folder-tree projects · pre-open sessions by agent (Claude Code, Codex, Gemini, …) · terminal tabs + splits · "always running" menu-bar monitor · integrated browser · Ghostty theming · socket/CLI/MCP control.

## The app

[`macos/SacredTerminal/`](macos/SacredTerminal/) is a native **Swift + AppKit** app that embeds
**libghostty** for terminal rendering — exactly how cmux does it:

> **libghostty owns each terminal surface's PTY *and* its GPU (Metal) rendering.** The app creates a
> *surface*, points it at a command (the agent CLI) + working directory, hosts it in an `NSView`, and
> forwards input. Themes/fonts/colors come from `~/.config/ghostty/config`.

Built on top of that: a projects → agent-sessions rail, Ghostty-style tabs + splits, an integrated
WKWebView browser, settings, the `NSStatusItem` "always running" monitor, and a Unix-socket control
API with a `sacred` CLI. See [`macos/SacredTerminal/README.md`](macos/SacredTerminal/README.md) for the
architecture and how to build it on a Mac (it vendors Ghostty as a submodule into
`GhosttyKit.xcframework`, like cmux).

```bash
cd macos/SacredTerminal
git submodule update --init --recursive && ./scripts/build-ghostty.sh   # build libghostty (Mac + Zig)
swift run SacredTerminal
```

## Spec & design mock

- **Spec:** [`docs/specs/spec.md`](docs/specs/spec.md)
- **MCP setup:** [`docs/mcp/setup.md`](docs/mcp/setup.md)
- The zero-build HTML design mock (the visual source of truth) is preserved in
  [`docs/mock-design/`](docs/mock-design/) — `index.html` (main window) and `menu-bar.html`.
