# Known issues / follow-ups

Items that are **implemented and build-verified**, but still need a final
non-destructive manual hover/click pass before being removed. The controls now
also expose stable Accessibility labels/identifiers so a future computer-use pass
can target them without coordinate guessing.

Last updated for branch `claude/ultracode-workflows-spec-kcziv2`.

---

## 1. Quick-pick agent icons — hover-grow (needs visual confirmation)

**Change.** `RailViewController.AgentPillButton` now swaps its icon 16 → 20 px and
adds a faint backing on `mouseEntered` / `mouseExited`, so it's clear which agent a
click will launch.

**This pass.** The button now re-syncs hover from the live pointer after tracking
areas are installed or the row is rebuilt under the cursor. Each quick-pick button
also has an Accessibility label and identifier like `quick-pick-codex`, so UI
automation can locate the agent buttons directly.

**How to verify.** Hover a project folder in the rail so the quick-pick pill
appears, then move across the agent icons — each should visibly enlarge under the
cursor and shrink back when you leave it.

---

## 2. Session close button "×" (needs click confirmation)

**Change.** The per-session close button was a button *title* ("×"), and
`contentTintColor` doesn't color title text, so it rendered near-invisible on the
dark rail. It's now a tintable `xmark` SF Symbol, revealed on hover
(`RailViewController.SessionRow`).

**This pass.** The symbol is explicitly marked as a template image, the fallback
glyph path now restores text-mode rendering, and the button has a stable
Accessibility identifier (`session-close-<id>`). Computer Use confirmed the close
button appears in the rail tree/screenshot; the destructive close click itself was
left for manual confirmation so the saved session was not removed during this pass.

**How to verify.** Hover a session row — an **×** should appear on the right (where
the ⌘N hint sits). Clicking it should close that session
(`AppState.closeSession`).

---

## 3. Adding a second session from the hover pill (needs click confirmation)

**Change.** Creating a session rebuilds the rail, which recreates the hovered
project row *under* the cursor; `.assumeInside` on the tracking area suppressed the
synthetic `mouseEntered`, so the pill stayed hidden and a second session seemed
impossible to start. `RailViewController.ProjectRow` now re-derives hover from the
actual pointer position once laid out (`viewDidMoveToWindow` → async), so the pill
reappears immediately.

**This pass.** The pointer re-sync moved into the shared `HoverView`, so project
and session rows both recover hover state after rebuilds. Project-row hit testing
now uses the tracked hover state rather than animated `alphaValue`, which prevents
an immediate pill click from being misrouted to the row-collapse handler while the
pill is still fading in.

**How to verify.** Hover a project, click an agent to start a session; without
moving the mouse away, the pill should still be showing so you can click another
agent to add a second session.

---

## Resolved (kept for history)

- **Agent sessions froze (e.g. Gemini).** A GUI app launched via Finder/`open` has
  a minimal PATH, so CLIs under nvm / Homebrew / `~/.local/bin` weren't found and
  the PTY died. Fixed by importing the login-shell PATH at launch
  (`AppDelegate.importShellPath`) and resolving each command to an absolute path
  (`GhosttySurface.resolveExecutable`). Verified: Gemini boots its CLI.
- **Empty-state logo.** Removed the faint Claude ghost mark per feedback.
- **`.app` opened at 0×0 via Finder/`open`.** Fixed with the deferred launch-frame
  re-assert (commit `e33fb3e`).
- **Menu-bar dropdown was a native `NSMenu`.** Rebuilt as the mock's glass
  `NSPopover` (commit `e33fb3e`).
