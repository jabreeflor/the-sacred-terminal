# The Sacred Terminal — app

A **real** terminal workspace organized around projects and agents, modeled on
[cmux](https://github.com/manaflow-ai/cmux) and built **on top of Ghostty**.

- **Terminal engine:** [`ghostty-web`](https://github.com/coder/ghostty-web) — Ghostty's
  terminal core (libghostty) compiled to WebAssembly, the same engine cmux embeds natively.
- **Real PTYs:** a Node + `ws` + `node-pty` bridge spawns real shells / agent CLIs at each
  project's directory, streamed to the browser over a WebSocket. Sessions are *hosted* — a pty
  keeps running after its tab detaches and replays scrollback on reattach ("always running").
- **UI:** React + TypeScript + Vite. Project rail, agent-bound sessions, Ghostty-style terminal
  tabs + splits, an integrated browser pane, settings, and the menu-bar monitor — per
  [`../docs/specs/spec.md`](../docs/specs/spec.md).
- **Theme:** Ghostty's Catppuccin Frappé by default; swap any bundled palette in Settings →
  Appearance to re-skin every pane at once.

## Why a web app (and not the native Swift/AppKit cmux stack)

cmux itself is a native macOS app (Swift + AppKit + libghostty). This repo is developed in a
Linux cloud container with no macOS/AppKit, and Ghostty's embeddable C API isn't shipped yet — so
the faithful, *runnable-here* way to build "on top of Ghostty" is `ghostty-web` (libghostty in
WASM) plus a real `node-pty` backend. It runs in any browser and can later be wrapped in
Electron/Tauri for a desktop shell.

## Run

```bash
cd app
npm install            # builds node-pty natively; ghostty-web ships its wasm inline
npm run dev            # PTY bridge on :5174, Vite on :5173
open http://localhost:5173
```

If an agent CLI (`claude`, `codex`, `gemini`, …) is on your `PATH`, opening a session with that
agent launches the real CLI; otherwise the pane falls back to a real shell with a note. The
menu-bar "always running" monitor is at `http://localhost:5173/#menu-bar`.

## Layout

```
app/
  index.html
  vite.config.ts          # /pty ws proxy -> pty bridge
  server/pty-server.mjs   # node-pty <-> websocket, hosted sessions + scrollback replay
  src/
    main.tsx              # routes workspace vs #menu-bar
    App.tsx               # titlebar + rail + main + overlays + shortcuts
    store.ts              # zustand state (projects/sessions/panes), persisted
    ui.ts                 # ephemeral overlay state
    lib/ghostty.ts        # ghostty-web init + Catppuccin Frappé theme
    components/TerminalPane.tsx   # one ghostty-web terminal <-> one pty
    components/...         # rail, titlebar, picker, settings, browser, …
    pages/MenuBarMonitor.tsx
```
