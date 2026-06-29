# The Sacred Terminal — Spec

A terminal workspace in the spirit of [cmux](https://github.com/), built around **projects and agents** instead of raw terminal tabs.

> Status: **prototype**. The interactive mock lives at [`../mock-design/index.html`](../mock-design/index.html).

---

## 1. What it is

A desktop terminal where the unit of work is a **session bound to an agent** (Claude Code, Codex, Cursor, Gemini, …), organized under **projects** in a collapsible side rail. You see at a glance which agents are working, which need your input, and which are done — and you can pre-open a fresh agent session under any project in two clicks.

It is *not* a tab-based terminal. There are no terminal tabs; one session is active in the main pane at a time, chosen from the rail.

## 2. Goals

- **Project-first organization** — a minimal folder tree, not a flat tab strip.
- **Agent-first sessions** — every session knows which agent it runs and surfaces that agent's live state.
- **Configurable side rail** — collapse/expand on demand (à la cmux), so the terminal can go full-width.
- **Ghostty look** — import Ghostty's color theme so the terminal feels native to that ecosystem.
- **Stay simple** — the prototype deliberately omits terminal tabs, splits, and settings UI.

## 3. Non-goals (for the prototype)

- No real PTY / process spawning (banners are faux output).
- No terminal tabs, panes, or splits.
- No multi-window, themes UI, or settings screen.
- No auth / accounts.

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
│ ● ● ●  [▢]  ✳ cmux                          ⌘B rail · ⌘N new │  titlebar
├───────────────┬────────────────────────────────────────────┤
│ PROJECTS   +  │  ✳ Claude Code  ~/project        ● Working   │  session header
│ ▾ 📁 project  │ ──────────────────────────────────────────── │
│   ✳ Claude    │                                              │
│      working… │     terminal pane (Ghostty theme)            │
│   >_ shell    │                                              │
│ ▸ 📁 other    │                                              │
│               │ ──────────────────────────────────────────── │
│ + Add project │  ✳ message Claude Code…                      │  input
├───────────────┴────────────────────────────────────────────┤
│ ✳ cmux  project › session        ghostty: catppuccin-frappe │  statusbar
└────────────────────────────────────────────────────────────┘
```

- **Side rail** (left): project tree. Toggle with `⌘B` or the titlebar button. Fully collapses; main pane reflows to full width.
- **Main pane** (right): the active session — header (agent · path · status chip), terminal output, and an input row. No tabs.
- **Statusbar** (bottom): app marker, breadcrumb, active Ghostty theme, project/session counts.

## 6. Interactions

| Action | Trigger |
|---|---|
| Toggle side rail | `⌘B` / titlebar sidebar button |
| Pre-open a session by agent | per-project `+` (on hover) or `⌘N` → agent picker |
| Add a project | rail header `+` or "Add project" button → name + path modal |
| Switch active session | click a session in the rail |
| Close a session | hover a session → `×` |
| Collapse/expand a project | click the project row |
| Send to the active agent | type in the input row, `Enter` (flips status to `working`) |
| Dismiss picker / modal | `Esc` or click the scrim |

## 7. Agent pre-opening (the Orca pattern)

Clicking `+` on a project (or `⌘N`) opens a picker: **"Pre-open a session with…"** listing the available agents with their glyph and provider. Selecting one immediately creates a session in that project, bound to that agent, set to `working` (or `idle` for Shell), and makes it active.

Default agent roster:

| Agent | Provider | Glyph |
|---|---|---|
| Claude Code | Anthropic · Opus 4.8 | ✳ |
| Codex | OpenAI · gpt-5 | ⬡ |
| Cursor Agent | Cursor CLI | ▸ |
| Gemini | Google · 2.5 Pro | ✦ |
| Copilot | GitHub | ◐ |
| OpenCode | open source | ◇ |
| Shell | zsh | >_ |

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

## 10. Persistence

Prototype stores the full tree (projects, sessions, rail state, active session) in `localStorage` under `cmux-proto`, so state survives a refresh. Production would back this with real session/process state.

## 11. Open questions

- Slim icon-rail vs. full collapse?
- Drag-to-reorder sessions / projects?
- Real terminal (xterm.js + PTY) and worktree isolation per agent session (cf. Orca)?
- Where do agent definitions live — built-in list vs. user-configurable?
