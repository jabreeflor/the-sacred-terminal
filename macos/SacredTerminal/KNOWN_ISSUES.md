# Known issues

## Menu-bar dropdown is a native `NSMenu`, not the mock's custom glass popover

The mock (`docs/mock-design/menu-bar.html`) is a 440pt blurred glass panel with
two-line rows, per-status spinners, and trailing agent brand icons. The app's
`StatusItemController` uses a native `NSMenu` with two-line attributed titles +
a colored status dot. The high-value parity fixes are done (mock row ordering —
working first, "needs your input" last below a separator; the `#2f6fed` notify
badge; the "Needs your input" label), but a full 1:1 match needs an `NSPopover`
with a custom `NSView` content (glass material, brand icons, animated spinners).
That's a larger rebuild, deferred.


## Packaged `.app` opens with a zero-size window when launched via Finder / `open`

**Symptom.** After `scripts/package-app.sh`, double-clicking `SacredTerminal.app`
(or `open .build/SacredTerminal.app`) launches the process but shows **no usable
window** — `CGWindowList` reports the app's window(s) at `0 × 0`. The Dock icon
appears and the menu bar is present, but there's nothing to interact with.

**What works.** Running the built binary **directly** opens the window correctly
at the intended 1240 × 800:

```bash
swift build
.build/debug/SacredTerminal            # or: swift run SacredTerminal
# or the binary inside the bundle:
.build/SacredTerminal.app/Contents/MacOS/SacredTerminal
```

So this is a *launch-path* problem (LaunchServices), not a layout bug — the same
binary lays out fine when started as a plain process.

**Repro.**
1. `bash scripts/package-app.sh debug`
2. `open .build/SacredTerminal.app`
3. `CGWindowListCopyWindowInfo(...)` shows the window bounds as `0 × 0`.

**Suspected cause.** The window's content size is driven by the content view
controller's Auto Layout fitting size. When the app is started by LaunchServices,
the window is sized/ordered-in before that fitting size is established, so it
settles at `0 × 0` instead of the content's required minimum (1240 × 800), and the
post-`showWindow` re-assert doesn't take. The direct-launch timing happens to
establish the size before the window is shown. Stale window state restoration was
ruled out (cleared `~/Library/Saved Application State/com.sacred.terminal.savedState`
and `defaults delete com.sacred.terminal` — no change). Multiple lingering
instances surviving `kill -9` were also observed and may compound it.

**Workaround.** Launch the binary directly (above) for development.

**Status.** Open. Likely fixes to try:
- Set the window frame in `applicationDidFinishLaunching` *after* `showWindow`, on a
  deferred runloop tick, with `setFrame(_:display:)` (a stronger re-assert than the
  current `showWindow` override).
- Or give the window an explicit `setFrameAutosaveName` + a sane default frame so
  LaunchServices restores a real size.
- Or move off content-VC-driven sizing entirely (host the root via a plain
  `contentView` that the window does not auto-size to).
- Ensure single-instance behaviour so leftover processes don't fight over windows.
