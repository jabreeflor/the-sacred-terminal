# The Sacred Terminal — Spec

A terminal workspace in the spirit of [cmux](https://github.com/), built around **projects and agents** instead of raw terminal tabs.

> Status: **prototype**. Interactive mocks:
> - Main window — [`../mock-design/index.html`](../mock-design/index.html)
> - Menu-bar monitor ("Always running") — [`../mock-design/menu-bar.html`](../mock-design/menu-bar.html)
> - Logo review — [`../mock-design/logo-review.html`](../mock-design/logo-review.html)

---

## 1. What it is

A desktop terminal where the unit of work is a **session bound to an agent** (Claude Code, Codex, Cursor, Gemini, …), organized under **projects** in a collapsible side rail. You see at a glance which agents are working, which need your input, and which are done — and you can pre-open a fresh agent session under any project in two clicks.

It is *not* a tab-based terminal. There are no terminal tabs; one session is active in the main pane at a time, chosen from the rail.

## 2. Goals

- **Project-first organization** — a minimal folder tree, not a flat tab strip.
- **Agent-first sessions** — every session knows which agent it runs and surfaces that agent's live state.
- **Configurable side rail** — collapse/expand on demand (à la cmux), so the terminal can go full-width.
- **Ghostty look** — import Ghostty's color theme so the terminal feels native to that ecosystem.
- **Stay simple** — the prototype deliberately omits terminal tabs, splits, and a full settings screen (a tabbed settings mock exists; most git fields are visual-only).

## 3. Non-goals (for the prototype)

- No real PTY / process spawning (banners are faux output).
- No terminal tabs or arbitrary pane splits (only terminal + integrated browser).
- No multi-window or auth / accounts.
- Browser preview uses a mock HTML page, not a real webview/PTY socket API.

## 4. Core concepts

| Concept | Description |
|---|---|
| **Project** | A folder on disk (name + path). Collapsible. Holds zero or more sessions. |
| **Session** | A terminal bound to one **agent**, with a **status** and a short **detail** line. |
| **Agent** | The CLI that drives a session: Claude Code, Codex, Cursor Agent, Gemini, Copilot, OpenCode, or plain Shell. |
| **Status** | `working` · `waiting` (needs input) · `idle` · `done`. Drives the rail's dot color, label, and pulse. |

## 5. Layout

```
┌────────────────────────────────────────────────────────────┐
│ ● ● ●  [▢]  [icon] Sacred          project › session  [🌐] main │  titlebar
├───────────────┬────────────────────────────────────────────┤
│  [⚙][+]       │                                              │
│ ▾ 📁 project  │     terminal pane (Ghostty theme)            │
│  [agent pill on project hover]                             │
│ + Add project │  [icon] message Claude Code…                 │  input
│               │  ┌─ browser (optional split) ─────────────┐  │
│               │  │ ← → ↻  localhost:5173              [×]   │  │
│               │  │        [live preview iframe]           │  │
│               │  └────────────────────────────────────────┘  │
├───────────────┴────────────────────────────────────────────┤
│ Sacred  project › session        ghostty: catppuccin-frappe │  statusbar
└────────────────────────────────────────────────────────────┘
```

- **Side rail** (left): Unpeel-style project tree — no section header; a `+` at the top opens import/create project. Gray folder icon + monospace project name; sessions are single-line rows (brand icon or spinner + task text) with global `⌘N` shortcuts. Hovering a project reveals a pill toolbar of brand agent icons.
- **Main pane** (right): terminal output and input only — session context (project › task, browser toggle, branch) lives in the **titlebar** (§5). Optional **integrated browser** split on the right (§12). No statusbar/footer.

## 6. Interactions

| Action | Trigger |
|---|---|
| Toggle side rail | `⌘B` / titlebar sidebar button |
| Toggle integrated browser | `⌘⌥B` / globe button in session header |
| Pre-open a session by agent | per-project hover pill (brand icons) or `⌘N` → agent picker |
| Add a project | rail top `+` → import folder or create new |
| Switch active session | click a session in the rail |
| Close a session | hover a session → `×` |
| Collapse/expand a project | click the project row |
| Send to the active agent | type in the input row, `Enter` (flips status to `working`) |
| Dismiss picker / modal | `Esc` or click the scrim |

## 7. Agent pre-opening (the Orca pattern)

Clicking an agent icon on a project's hover pill (or `⌘N`) opens a picker: **"Pre-open a session with…"** listing the available agents with their brand icon and provider. Selecting one immediately creates a session in that project, bound to that agent, set to `working` (or `idle` for Shell), and makes it active.

Default agent roster (vendored brand SVGs from [Lobe Icons](https://lobehub.com/icons) — no emoji or hand-drawn glyphs):

| Agent | Provider | Icon |
|---|---|---|
| Claude Code | Anthropic · Opus 4.8 | Claude (orange mark) |
| Codex | OpenAI · gpt-5 | OpenAI swirl |
| Cursor Agent | Cursor CLI | Cursor cube |
| Gemini | Google · 2.5 Pro | Gemini sparkle |
| Copilot | GitHub | Copilot badge |
| OpenCode | open source | Cline (stand-in) |
| Shell | zsh | terminal prompt |

Running sessions show an animated spinner in the rail instead of the static brand mark (`working` / `waiting`).

## 8. Status model

Single source of truth: `statusMeta(status)` → `{ label, color, pulse }`. This is the one deliberate design knob — it sets the rail's emotional tone (e.g. make `waiting` the loudest state since it needs you; keep `working` calm so a busy rail isn't alarming).

| Status | Meaning | Default treatment |
|---|---|---|
| `working` | Agent is running a turn | green dot, pulsing |
| `waiting` | Needs your input | amber dot, pulsing |
| `done` | Turn finished | blue dot, static |
| `idle` | Open but not running | grey dot, static |

## 9. Theming

Two independent token layers in a single `:root` block:

1. **App chrome** — cmux near-black (titlebar, rail, panels).
2. **Terminal** — Ghostty's default theme, **Catppuccin Frappé** (`bg #303446`, `fg #c6d0f5`, full 16-color ANSI palette).

Swapping any Ghostty palette into layer 2 re-skins every terminal pane at once.

### App Icon Direction

The app icon should use the **branching sacred timeline** direction: a luminous white/cyan energy trunk with blue glow and subtle magenta branch tips, filling a rounded-square macOS icon. Do not use an inner circular portal; the branches are the mark. Current preferred candidate: `sacred-terminal-app-icon-v6-thick-dark-border.png`, with a thick dark indigo/violet rounded-square rim and a deep navy background so the icon shape separates from black UI surfaces.

Reference materials:

- Visual reference — `../mock-design/assets/reference-sacred-tree.png`
- Logo review — [`../mock-design/logo-review.html`](../mock-design/logo-review.html)
- Generated candidate — [`../mock-design/assets/sacred-terminal-app-icon-v6-thick-dark-border.png`](../mock-design/assets/sacred-terminal-app-icon-v6-thick-dark-border.png)

## 10. Persistence

Prototype stores the full tree (projects, sessions, rail state, active session) in `localStorage` under `cmux-proto`, so state survives a refresh. Production would back this with real session/process state.

## 11. Always running — the menu-bar monitor

> Mock: [`../mock-design/menu-bar.html`](../mock-design/menu-bar.html) · preview: `screenshots/preview-menu-bar.png`

The window is disposable; the work is not. Closing the window must never stop an agent.

- **Hosted processes.** Every session runs in its own long-lived host process, independent of any window. Quitting or closing the window leaves sessions running.
- **Menu-bar item ("the pulse").** A persistent macOS menu-bar item keeps a live pulse on all sessions across all projects:
  - **Spins** whenever any agent is `working`.
  - **Rings** (animated ring + notify badge) whenever any session is `waiting` (needs you).
  - Idle/quiet when nothing is running.
- **The roster.** Clicking the item opens a dropdown listing active sessions — newest/most-relevant first, grouped roughly by recency, with a separator above items that need attention. Each row shows:

  | Element | Meaning |
  |---|---|
  | left indicator | per-session state — a spinner while `working`, an app glyph when idle |
  | title | the latest message / task, truncated |
  | subtitle | the project (e.g. `acme-storefront`) |
  | right identity | the agent's brand icon, or a blue dot when the session needs you / has unread output |

- **Snap-back.** Picking a row reopens the window focused **directly on that conversation** — no hunting through the rail.
- **Shared status source.** The pulse, the rail dots, and the roster all read the same `statusMeta(status)` model (§8), so a session's state looks consistent everywhere it appears.

This is the "window closed" counterpart to the main window (§5): same sessions, same statuses, surfaced through the OS chrome instead of the app chrome.

## 12. Integrated browser

A browser pane lives **inside** the workspace, so you can preview what an agent is building — and let the agent drive the page — without leaving the terminal. This mirrors [cmux's browser](https://manaflow-ai-cmux.mintlify.app/features/browser).

**In the mock:** [`../mock-design/index.html`](../mock-design/index.html) splits the main pane when a session's browser is open. Preview content comes from [`../mock-design/browser-preview.html`](../mock-design/browser-preview.html) (marketing hero or Storybook, keyed by project). Clicking an element in the preview posts a **send-to-agent** toast with an element ref.

- **Split pane.** Open a browser beside the active session's terminal (`⌘⌥B` or the globe button in the session header). Per-session: each session stores its own `browserUrl` and `browserOpen` state (persisted in `localStorage`).
- **Chrome.** Back / forward / reload (mock), editable URL bar, close button.
- **One programmable surface (production).** Both you and the agent drive the same browser over a socket API: navigate, snapshot the DOM / accessibility tree, click, type, fill forms, evaluate JS, and read console + network activity.
- **Element refs, not coordinates.** A snapshot returns a JSON accessibility tree with stable element refs; the agent acts on a ref instead of guessing pixels:

  ```
  browser snapshot                          # a11y tree -> refs
  browser navigate <url>
  browser click  --ref <element-ref>
  browser fill   --ref <element-ref> --value "…"
  browser eval   "document.title"
  ```

- **Send-to-agent.** Click any element in the browser to hand its **ref + HTML/CSS + a cropped screenshot** to the active agent — so "make this button match the design" just works (cf. Orca's click-to-context).
- **Closed feedback loop.** Console errors and failed network requests stream back to the agent automatically, closing build → preview → fix inside one window.
- **Chrome.** Address bar + back/forward/reload; auto-reload follows the dev server.

Because the browser is bound to a **session** (§4), it inherits that session's agent — whichever agent owns the terminal also owns the browser, and its actions show up in the same status/pulse model (§8, §11).

## 13. Open questions

- Slim icon-rail vs. full collapse?
- Drag-to-reorder sessions / projects?
- Real terminal (xterm.js + PTY) and worktree isolation per agent session (cf. Orca)?
- Where do agent definitions live — built-in list vs. user-configurable?
- Hosted-process model: per-session daemon vs. one supervisor process? How are sessions reattached after a full app restart (not just window close)?
- Menu-bar roster: cap the list length, or scroll? How is "needs you" ordered against plain recency?
- Integrated browser: bundle a webview (WKWebView/Chromium) or reuse the system one? Browser split per session vs. one shared browser that follows the active session?
