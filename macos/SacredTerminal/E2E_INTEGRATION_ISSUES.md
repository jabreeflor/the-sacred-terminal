# E2E Integration Issues

Central coordination log for the Sacred Terminal end-to-end integration test effort.

## Ground Rules

- This file is the single issues ledger for spawned Codex investigation threads.
- Investigation threads should not fix product code unless explicitly reassigned to the fix phase.
- Keep findings evidence-backed with file paths, commands, observed output, and reproduction notes.
- Categorize every issue so the follow-up fix thread can prioritize without guessing.
- If a behavior is already known or expected-broken, mark it as `known-broken` instead of treating it as a blocker.

## Categories

- `blocker`: prevents the integration harness or app launch from running at all.
- `product-bug`: real app behavior appears broken.
- `testability`: app needs seams, env overrides, accessibility identifiers, fixtures, or logging to test safely.
- `flaky-risk`: likely unstable under automation, parallel runs, hover/focus, timing, or macOS permissions.
- `known-broken`: behavior appears broken but should be quarantined rather than fixed in the first harness pass.
- `question`: needs product/design decision before implementation.

## Issue Template

```md
### ISSUE-ID: Short Title

- Category:
- Severity: blocker | high | medium | low
- Owner thread:
- Status: open | investigated | fixed | deferred
- Evidence:
- Reproduction:
- Suggested next step:
```

## Harness And Isolation Findings

<!-- worker:harness-isolation:start -->
### HARN-ISO-001: HOME/XDG Overrides Do Not Isolate Application Support State

- Category: blocker
- Severity: blocker
- Owner thread: worker:harness-isolation
- Status: fixed
- Evidence: `Persistence.fileURL` writes `session.json` under `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` with a fallback to `NSHomeDirectory()` (`Sources/SacredTerminal/Persistence/SessionSnapshot.swift:17-23`). `SocketServer.socketPath()` and `sacred` use the same user-domain Application Support lookup for `SacredTerminal/control.sock` (`Sources/SacredTerminal/Socket/SocketServer.swift:24-33`, `Sources/sacred-cli/main.swift:24-34`). On this host, overriding `HOME` and `XDG_CONFIG_HOME` did not redirect Foundation's user-domain lookup:

  ```bash
  env HOME=/tmp/sacred-e2e-home.9hUWIX XDG_CONFIG_HOME=/tmp/sacred-e2e-home.9hUWIX/.config swift -e 'import Foundation; print(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? "nil")'
  ```

  Observed output:

  ```text
  /Users/jabreeflor/Library/Application Support
  ```

  ```bash
  env HOME=/tmp/sacred-e2e-home.9hUWIX XDG_CONFIG_HOME=/tmp/sacred-e2e-home.9hUWIX/.config swift -e 'import Foundation; print(NSHomeDirectory())'
  ```

  Observed output:

  ```text
  /Users/jabreeflor
  ```

  Running the CLI with the same temporary env still found the user's live app socket:

  ```bash
  env HOME=/tmp/sacred-e2e-home.9hUWIX XDG_CONFIG_HOME=/tmp/sacred-e2e-home.9hUWIX/.config swift run sacred status
  ```

  Observed output:

  ```text
  [0/1] Planning build
  Building for debugging...
  [0/3] Write swift-version--58304C5D6DBC2206.txt
  Build of product 'sacred' complete! (0.11s)
  The Sacred Terminal is running.
  ```

- Reproduction: Create a temp HOME, run the two `swift -e` commands above from `macos/SacredTerminal`, then run `swift run sacred status` with that temp HOME. The CLI still resolves the real account's Application Support path.
- Suggested next step: Add a single runtime-path seam used by both app and CLI, for example `SACRED_TERMINAL_E2E_ROOT` or `SACRED_TERMINAL_APP_SUPPORT_DIR`, and derive `session.json` plus `control.sock` from it before any `AppState`, `Persistence`, or `SocketServer` singleton is created. XCTest should create a per-test temp root and launch both the app and CLI with the same override.
- Fix-phase update: Added `SACRED_TERMINAL_APP_SUPPORT_DIR` via `SacredTerminalSupport`; `Persistence`, `SocketServer`, and `sacred` all resolve `session.json`/`control.sock` from it. The SwiftPM E2E tests create one short `/tmp` support directory per test.

### HARN-ISO-002: Test App Launch Can Unlink Or Steal The User's Live Control Socket

- Category: flaky-risk
- Severity: high
- Owner thread: worker:harness-isolation
- Status: fixed
- Evidence: `SocketServer.start()` unconditionally removes the resolved socket path before binding (`Sources/SacredTerminal/Socket/SocketServer.swift:69-72`), and `AppDelegate` starts the socket with `try? socket?.start()` so startup failures are swallowed (`Sources/SacredTerminal/AppDelegate.swift:44-46`). The real user path currently contains a live socket and persisted session file:

  ```bash
  ls -l /Users/jabreeflor/Library/Application\ Support/SacredTerminal
  ```

  Observed output:

  ```text
  total 8
  srw-------@ 1 jabreeflor  staff     0 Jun 30 20:47 control.sock
  -rw-r--r--@ 1 jabreeflor  staff  2175 Jun 30 20:49 session.json
  ```

- Reproduction: With the user's app running, launch another app instance without an isolated socket path. The new instance resolves the same `control.sock`, unlinks that pathname, then binds it for itself if possible. Even if binding fails, the app gives no harness-visible error because the throw is ignored.
- Suggested next step: Require an isolated socket path for E2E launch and fail loudly in E2E mode if the socket cannot start. Consider refusing to unlink an existing socket unless it is inside the configured E2E temp root, or probe ownership/liveness before unlinking.
- Fix-phase update: E2E launches use isolated support dirs and `SACRED_TERMINAL_E2E=1`; socket startup failures now emit a concrete stderr diagnostic and terminate the app in E2E mode. Production behavior is unchanged when the env vars are absent.

### HARN-ISO-003: Launching The Real App Can Restore User Sessions And Spawn Real PTYs/Agent CLIs

- Category: blocker
- Severity: blocker
- Owner thread: worker:harness-isolation
- Status: fixed
- Evidence: `AppState` loads persisted state during singleton initialization (`Sources/SacredTerminal/State/AppState.swift:72-82`) from the real `session.json` path above. `WorkspaceViewController.rebuild()` immediately reads `AppState.shared.activeContext` (`Sources/SacredTerminal/Views/WorkspaceViewController.swift:67-68`), creates a `SurfaceView` for the active pane with `directory: project.path` (`Sources/SacredTerminal/Views/WorkspaceViewController.swift:505-514`), and `SurfaceView.viewDidMoveToWindow()` creates `GhosttySurface` on the next main runloop tick (`Sources/SacredTerminal/Ghostty/SurfaceView.swift:39-45`). `GhosttySurface` hands libghostty the command and working directory (`Sources/SacredTerminal/Ghostty/GhosttyBridge.swift:130-154`); agent commands include real `claude`, `codex`, `cursor-agent`, etc. with yolo flags enabled by default for supported agents (`Sources/SacredTerminal/Models/Agent.swift:20-41`, `Sources/SacredTerminal/State/AppState.swift:126-134`).
- Reproduction: Launching `swift run SacredTerminal` or `open .build/SacredTerminal.app` without isolated state will read the user's real snapshot. If that snapshot has an active session, the app can create real Ghostty PTYs in real project directories and start real shells/agent CLIs. I did not run the app launch probe after confirming the isolation leak above because it would operate on the user's real state.
- Suggested next step: Seed E2E with an isolated fixture snapshot and add an E2E launch mode that either starts with empty state or disables Ghostty surface creation until the test explicitly requests it. For full integration tests that need a real PTY, point the session at a temp project directory and a deterministic command such as `/bin/zsh -f` or a fixture script, not the user's persisted agent sessions.
- Fix-phase update: The first SwiftPM E2E slice launches only with an isolated `SACRED_TERMINAL_APP_SUPPORT_DIR` and sets `SACRED_TERMINAL_DISABLE_GHOSTTY_SURFACES=1`, so seeded sessions exercise state/socket behavior without spawning real user PTYs or agent CLIs.

### HARN-ISO-004: App Launch Imports User Shell PATH And Ghostty Config

- Category: testability
- Severity: high
- Owner thread: worker:harness-isolation
- Status: fixed
- Evidence: `AppDelegate.applicationDidFinishLaunching` always calls `importShellPath()` before building the window (`Sources/SacredTerminal/AppDelegate.swift:8-14`), and `importShellPath()` runs `$SHELL -ilc 'printf %s "$PATH"'` then mutates process `PATH` (`Sources/SacredTerminal/AppDelegate.swift:87-101`). `GhosttyApp` loads libghostty default config files (`Sources/SacredTerminal/Ghostty/GhosttyBridge.swift:29-35`) and the app's theme detection scans `XDG_CONFIG_HOME`, `~/.config/ghostty/config`, and `~/Library/Application Support/com.mitchellh.ghostty/config` using `NSHomeDirectory()` (`Sources/SacredTerminal/Ghostty/GhosttyBridge.swift:101-121`). Since `NSHomeDirectory()` resolved to `/Users/jabreeflor` even with a temp `HOME`, an E2E launch can read user shell startup files and user Ghostty config.
- Reproduction: Run the `NSHomeDirectory()` probe from HARN-ISO-001, then inspect the unconditional calls in `AppDelegate` and `GhosttyBridge`. Any XCTest app launch without additional seams will inherit user shell/config behavior.
- Suggested next step: Add deterministic E2E env controls: skip login-shell PATH import, pass a known `PATH`/`SHELL`, and either disable Ghostty default-file loading or force a temp `XDG_CONFIG_HOME`/config path that libghostty and `userConfiguredTheme()` both honor.
- Fix-phase update: E2E mode skips login-shell PATH import, uses a test-provided `PATH`/`SHELL`, and disables Ghostty surface startup for the first harness pass. Full Ghostty config isolation remains out of scope until surface-level tests are enabled.

### HARN-ISO-005: SwiftPM Has No XCTest Harness Target Yet

- Category: testability
- Severity: medium
- Owner thread: worker:harness-isolation
- Status: fixed
- Evidence: `Package.swift` declares two executable products/targets and one binary target, but no `testTarget` (`Package.swift:16-50`). There is no `Tests` directory:

  ```bash
  find Tests -maxdepth 3 -print
  ```

  Observed output:

  ```text
  find: Tests: No such file or directory
  ```

  `swift build` succeeds:

  ```bash
  swift build
  ```

  Observed output:

  ```text
  [0/1] Planning build
  Building for debugging...
  [0/5] Write swift-version--58304C5D6DBC2206.txt
  Build complete! (0.14s)
  ```

  `swift test` has no target to run:

  ```bash
  swift test
  ```

  Observed output:

  ```text
  Another instance of SwiftPM (PID: 33291) is already running using '/Users/jabreeflor/Documents/github_repos/the-sacred-terminal/macos/SacredTerminal/.build', waiting until that process has finished execution...[0/1] Planning build
  Building for debugging...
  [0/5] Write swift-version--58304C5D6DBC2206.txt
  Build complete! (0.11s)
  error: no tests found; create a target in the 'Tests' directory
  ```

- Reproduction: Run `swift test` from `macos/SacredTerminal`.
- Suggested next step: Add a dedicated E2E test target or external XCTest harness that launches the built app/CLI as subprocesses with the isolation env from HARN-ISO-001. Because `SacredTerminal` is currently executable-only and not an importable library target, keep product-code factoring minimal at first: the harness can black-box launch binaries until a shared runtime-path helper is introduced.
- Fix-phase update: Added `SacredTerminalIntegrationTests`, a black-box SwiftPM XCTest target under `Tests/` that launches the built app/CLI subprocesses.
<!-- worker:harness-isolation:end -->

## Socket And CLI Findings

<!-- worker:socket-cli:start -->
### SC-001: Socket/CLI isolation is not controlled by `HOME`

- Category: testability
- Severity: high
- Owner thread: socket-cli worker
- Status: fixed
- Evidence:
  - `macos/SacredTerminal/Sources/SacredTerminal/Socket/SocketServer.swift:24-33` and `macos/SacredTerminal/Sources/sacred-cli/main.swift:24-34` both resolve `control.sock` through Foundation's `.applicationSupportDirectory`.
  - Command: `swift build --product sacred` from `macos/SacredTerminal`; observed `Build of product 'sacred' complete! (0.13s)`.
  - Command: `HOME=/tmp/sacred-e2e-empty-home .build/debug/sacred status; printf "exit=%d\n" "$?"`; observed `The Sacred Terminal is running.` and `exit=0`, proving a temp `HOME` did not isolate the CLI from the live user socket.
  - Command: `HOME=/tmp/sacred-e2e-empty-home-ls .build/debug/sacred ls; printf "exit=%d\n" "$?"`; observed a live sessions table and `exit=0`, again using the real app state despite the temp `HOME`.
  - Command: `CFFIXED_USER_HOME=/tmp/sacred-e2e-cfhome .build/debug/sacred status; printf "exit=%d\n" "$?"`; observed `The Sacred Terminal is not running.` and `exit=1`, so CoreFoundation's home override can isolate the CLI if the app is launched with the same environment.
- Reproduction:
  - Launch or run CLI commands with only `HOME` pointed at a temp directory while a normal Sacred Terminal app is running; the CLI still reaches `~/Library/Application Support/SacredTerminal/control.sock`.
- Suggested next step:
  - Add an explicit app/CLI override such as `SACREDTERMINAL_APP_SUPPORT_DIR` or `SACRED_SOCKET_PATH`; until then, the E2E harness must launch both app and CLI with `CFFIXED_USER_HOME` and a short temp path.
- Fix-phase update: Added canonical `SACRED_TERMINAL_APP_SUPPORT_DIR`; `CFFIXED_USER_HOME` is no longer needed for isolation.

### SC-002: App silently ignores socket startup failures

- Category: product-bug
- Severity: high
- Owner thread: socket-cli worker
- Status: fixed
- Evidence:
  - `macos/SacredTerminal/Sources/SacredTerminal/AppDelegate.swift:45-46` creates `SocketServer()` and calls `try? socket?.start()`, discarding `pathTooLong`, `bind`, and `listen` failures.
  - `macos/SacredTerminal/Sources/SacredTerminal/Socket/SocketServer.swift:80-101` can throw on AF_UNIX path length or bind failure, but no launch diagnostic reaches the CLI or harness.
- Reproduction:
  - Launch the app with an overlong Application Support path or an otherwise failing socket bind; the app can continue running while `sacred status` reports only that the app is not running/no socket.
- Suggested next step:
  - Log socket startup failures with the concrete path/errno and expose a deterministic readiness signal for E2E, or fail app launch in test mode when the control socket cannot start.
- Fix-phase update: Socket startup failures now log their concrete error. In `SACRED_TERMINAL_E2E=1`, the app exits nonzero; XCTest covers an overlong socket path failure.

### SC-003: Protocol behaves as one request per connection

- Category: testability
- Severity: medium
- Owner thread: socket-cli worker
- Status: deferred
- Evidence:
  - File comments describe newline-delimited JSON as "Each line in is one command; each line out is one JSON reply," but `macos/SacredTerminal/Sources/SacredTerminal/Socket/SocketServer.swift:151-176` reads until the first newline, handles that one line, writes one reply, and closes the fd.
  - Command: a Python AF_UNIX client sent `{"cmd":"status"}\n{"cmd":"status"}\n` to the live socket.
  - Observed output: `two-status-lines: {"ok":true}` followed by EOF; no second reply was emitted.
- Reproduction:
  - Keep one socket connection open and write multiple JSON lines; only the first command is processed.
- Suggested next step:
  - Either document the protocol as one command per connection and make the harness open a fresh connection for every command, or update `serve(_:)` to process multiple newline-delimited commands per connection.
- Fix-phase update: Deferred. The first harness treats the current behavior as one command per connection and opens a fresh socket for each raw probe.

### SC-004: CLI output and errors are human-oriented only

- Category: testability
- Severity: medium
- Owner thread: socket-cli worker
- Status: deferred
- Evidence:
  - `macos/SacredTerminal/Sources/sacred-cli/main.swift:213-249` renders `ls` as a padded/truncated table or `No sessions.`, with no `--json` option.
  - `macos/SacredTerminal/Sources/sacred-cli/main.swift:184-187` collapses server failures to a single English `error` string, and `main.swift:267-280` special-cases `status` by printing a human sentence and exiting `1` when not running.
  - Command: `CFFIXED_USER_HOME=/tmp/sacred-e2e-cfhome-ls .build/debug/sacred ls; printf "exit=%d\n" "$?"`; observed `sacred: The Sacred Terminal does not appear to be running (no socket at /tmp/sacred-e2e-cfhome-ls/Library/Application Support/SacredTerminal/control.sock). Launch the app first.` and `exit=1`.
  - Command: `.build/debug/sacred focus; printf "exit=%d\n" "$?"`; observed `usage: sacred focus <id>` and `exit=2`.
- Reproduction:
  - Attempt to assert CLI `ls`, `status`, `focus`, or `new-session` outcomes from automation; tests must parse English/table output or bypass the CLI and speak raw socket JSON.
- Suggested next step:
  - Add `--json` output for CLI commands and structured server error codes such as `app_not_running`, `missing_cmd`, `unknown_agent`, `no_project`, and `no_session`.
- Fix-phase update: Deferred. The first harness asserts stable human output where needed and uses raw socket JSON for protocol-level checks.

### SC-005: `focus` and `new-session` are real persistent mutations

- Category: testability
- Severity: high
- Owner thread: socket-cli worker
- Status: fixed
- Evidence:
  - `macos/SacredTerminal/Sources/SacredTerminal/Socket/SocketServer.swift:269-275` handles `focus` by calling `AppState.shared.setActive(id)` and posting `.sacredFocusSession`.
  - `macos/SacredTerminal/Sources/SacredTerminal/Socket/SocketServer.swift:278-287` handles `new-session` by calling `AppState.shared.createSession(...)`.
  - `macos/SacredTerminal/Sources/SacredTerminal/State/AppState.swift:111` and `AppState.swift:125-137` both end in `changed()`, and `AppState.swift:221-223` persists and broadcasts the change.
  - Non-mutating error probes against the live socket produced structured failures: `focus-no-such-session: {"ok":false,"error":"no session \"__sacred_e2e_missing__\""}` and `new-no-such-project: {"ok":false,"error":"no project \"__sacred_e2e_missing__\""}`.
- Reproduction:
  - Run `sacred focus <real-session-id>` or `sacred new <real-project-id> shell` against the normal user socket; the app active session/session list changes and persists.
- Suggested next step:
  - Gate mutating E2E cases behind isolated fixture state, preferably the same explicit support-dir/socket override from SC-001, and add a fixture seed/reset path before enabling positive `focus` and `new-session` tests.
- Fix-phase update: Added isolated seeded fixture coverage for `sacred ls`, `sacred focus`, and `sacred new`; tests run with disabled Ghostty surfaces and temp project paths.

### SC-006: Empty malformed requests get EOF instead of structured JSON

- Category: flaky-risk
- Severity: low
- Owner thread: socket-cli worker
- Status: deferred
- Evidence:
  - `macos/SacredTerminal/Sources/SacredTerminal/Socket/SocketServer.swift:167-170` closes the fd when the trimmed line is empty, without writing an error object.
  - Command: a Python AF_UNIX client sent `\n` to the live socket.
  - Observed output: `empty-line-bytes=0 payload=b''`.
- Reproduction:
  - Send a blank line as the command frame; the client receives EOF, while non-empty malformed JSON receives `{"error":"invalid JSON","ok":false}`.
- Suggested next step:
  - Return a structured `missing cmd` or `invalid JSON` response for empty command frames, or make the E2E malformed-JSON tests avoid blank lines explicitly.
- Fix-phase update: Deferred. The first raw malformed test covers non-empty malformed JSON, missing `cmd`, and unknown command; blank frames remain quarantined.

### SC-007: Non-socket files at the control path produce raw errno text

- Category: flaky-risk
- Severity: low
- Owner thread: socket-cli worker
- Status: fixed
- Evidence:
  - `macos/SacredTerminal/Sources/sacred-cli/main.swift:76-110` maps `ECONNREFUSED` and `ENOENT` to `notRunning`, but not `ENOTSOCK`.
  - Command: create a regular file at `/tmp/sacred-e2e-stale-file-home/Library/Application Support/SacredTerminal/control.sock`, then run `CFFIXED_USER_HOME=/tmp/sacred-e2e-stale-file-home .build/debug/sacred status; printf "exit=%d\n" "$?"`.
  - Observed output: `sacred: could not connect to /tmp/sacred-e2e-stale-file-home/Library/Application Support/SacredTerminal/control.sock: Socket operation on non-socket` and `exit=1`.
  - Control case: creating a stale AF_UNIX socket file with no listener under `CFFIXED_USER_HOME=/tmp/sacred-e2e-stale-home` produced `The Sacred Terminal is not running.` and `exit=1`.
- Reproduction:
  - Leave a regular file or corrupted path entry at the expected `control.sock` location and run `sacred status`.
- Suggested next step:
  - Treat `ENOTSOCK` as a stale/not-running control path for `status`, or provide a cleanup command/harness helper that removes invalid `control.sock` entries in isolated test directories.
- Fix-phase update: `sacred status` now treats `ENOTSOCK` like not-running; XCTest covers a regular file at `control.sock`.

Validated non-blockers:

- Command: `swift build --product SacredTerminal` from `macos/SacredTerminal`; observed `Build of product 'SacredTerminal' complete! (0.17s)`.
- Raw socket probes against the live app returned structured errors for non-empty malformed or invalid commands: `not-json` -> `{"error":"invalid JSON","ok":false}`, `{}` -> `{"error":"missing \"cmd\"","ok":false}`, `{"cmd":"bogus"}` -> `{"error":"unknown cmd \"bogus\"","ok":false}`.
- Command-specific raw probes were also structured and non-crashing for missing focus id, missing new-session project, unknown agent, and missing project.
<!-- worker:socket-cli:end -->

## Persistence And Fixture Findings

<!-- worker:persistence-fixtures:start -->
### PF-001: E2E fixtures have no isolated persistence or socket location

- Category: testability
- Severity: high
- Owner thread: persistence-fixtures worker
- Status: fixed
- Evidence:
  - `macos/SacredTerminal/Sources/SacredTerminal/Persistence/SessionSnapshot.swift:17-22` always reads/writes `~/Library/Application Support/SacredTerminal/session.json`; there is no launch argument, environment override, or reset hook.
  - `macos/SacredTerminal/Sources/SacredTerminal/Socket/SocketServer.swift:24-33` and `macos/SacredTerminal/Sources/sacred-cli/main.swift:24-34` hard-code the same Application Support directory for `control.sock`.
  - `macos/SacredTerminal/Sources/SacredTerminal/Socket/SocketServer.swift:70-72` unlinks the socket path at startup, so a second app/test instance can disconnect or steal the shared control socket.
  - Command: `rg --files macos/SacredTerminal | rg "(^|/)Tests(/|$)|XCTest|UITest|\\.xcodeproj$|\\.xcworkspace$"` produced no output, and `Package.swift:20-50` contains only executable targets, so there is no existing XCTest fixture seam.
- Reproduction:
  - To seed projects/sessions before launching, a test currently has to write directly to the real per-user `session.json`; any run that forgets cleanup leaks into the next app launch.
  - Running two E2E jobs for the same macOS user would share both `session.json` and `control.sock`, and the later launch calls `unlink(path)` on the shared socket.
- Suggested next step:
  - Add an E2E-only storage namespace such as `SACREDTERMINAL_APP_SUPPORT_DIR`, used by `Persistence`, `SocketServer`, and `sacred-cli`, plus a launch/reset mode that can clear state or import a fixture from a temp directory before `AppState.shared` initializes.
- Fix-phase update: Added `SACRED_TERMINAL_APP_SUPPORT_DIR`; the XCTest harness writes full fixture snapshots into per-test support dirs before app launch.

### PF-002: Snapshot decoding is strict and failures are silent

- Category: product-bug
- Severity: high
- Owner thread: persistence-fixtures worker
- Status: deferred
- Evidence:
  - `macos/SacredTerminal/Sources/SacredTerminal/Persistence/SessionSnapshot.swift:5-13` declares `AppSessionSnapshot: Codable` with no tolerant decoder.
  - `macos/SacredTerminal/Sources/SacredTerminal/Models/Workspace.swift:4-78` declares `Pane`, `Session`, and `Project` as synthesized `Codable`; defaults in their initializers are not used when decoding missing keys.
  - `macos/SacredTerminal/Sources/SacredTerminal/Persistence/SessionSnapshot.swift:25-28` uses `try? JSONDecoder().decode(...)`, so malformed, old, or partially complete snapshots load as `nil` with no diagnostic.
  - Command: `swift -e 'import Foundation; final class Pane: Codable { let id: String; var started: Bool; init(id: String = "s1", started: Bool = false) { self.id = id; self.started = started } }; let data = #"{\"id\":\"s1\"}"#.data(using: .utf8)!; do { _ = try JSONDecoder().decode(Pane.self, from: data); print("decoded") } catch { print(error) }'`
  - Observed output: `keyNotFound(CodingKeys(stringValue: "started", intValue: nil), ... "No value associated with key CodingKeys(stringValue: \"started\"..."))`
- Reproduction:
  - Seed or keep an older snapshot missing fields such as `Pane.started`, `Session.browserOpen`, `Session.browserURL`, `Session.activePaneID`, or `Session.splitLayout`; app startup treats the whole snapshot as absent and starts empty.
- Suggested next step:
  - Add custom tolerant decoders with defaults for `AppSessionSnapshot`, `Project`, `Session`, and `Pane`, log decode failures, and add fixture decode tests that cover old/minimal snapshots.
- Fix-phase update: Deferred. The first harness uses complete fixture snapshots; tolerant decoding remains future persistence hardening.

### PF-003: Restored active IDs and pane state are not normalized

- Category: flaky-risk
- Severity: medium
- Owner thread: persistence-fixtures worker
- Status: fixed
- Evidence:
  - `macos/SacredTerminal/Sources/SacredTerminal/State/AppState.swift:236-245` applies decoded state directly and sets `activeSessionID = s.activeSessionID ?? firstSessionID`; a non-nil but stale `activeSessionID` is trusted.
  - `macos/SacredTerminal/Sources/SacredTerminal/State/AppState.swift:95-103` returns `nil` for an unknown active session, and `WorkspaceViewController.swift:77-81` then builds the empty state even if sessions exist elsewhere.
  - `macos/SacredTerminal/Sources/SacredTerminal/Models/Workspace.swift:59` falls back to `panes[0]` when `activePaneID` is stale; an empty decoded `panes` array can crash when the active session is rendered.
- Reproduction:
  - A fixture with valid projects/sessions but `activeSessionID: "missing"` restores to "No session open" instead of selecting the first session.
  - A fixture with an active session whose `panes` array is empty is accepted by decoding and can reach the unsafe `panes[0]` fallback.
- Suggested next step:
  - Normalize snapshots during `AppState.apply`: choose the saved active session only if it exists, otherwise first available session; ensure every session has at least one pane; ensure `activePaneID` belongs to that session.
- Fix-phase update: `AppState.apply` now normalizes stale active session IDs, empty pane arrays, and stale active pane IDs before views/socket commands use restored state.

### PF-004: ID generation is fixture-dependent and does not bump past project IDs

- Category: flaky-risk
- Severity: medium
- Owner thread: persistence-fixtures worker
- Status: fixed
- Evidence:
  - `macos/SacredTerminal/Sources/SacredTerminal/Models/Workspace.swift:85-90` uses a process-local monotonic `IDGen` starting at `s1`.
  - `macos/SacredTerminal/Sources/SacredTerminal/Models/Workspace.swift:71-77` gives projects generated IDs, but `macos/SacredTerminal/Sources/SacredTerminal/State/AppState.swift:245` bumps only restored session and pane IDs, not restored project IDs.
  - This makes generated IDs depend on prior persisted state and lets a project-only fixture with `id: "s1"` restore without advancing the counter.
- Reproduction:
  - Seed a project-only fixture with project ID `s1` and no sessions; after launch, adding another project can generate `s1` again because project IDs were not included in `IDGen.bump`.
  - Parallel or uncleared E2E runs cannot predict generated session/project IDs unless they fully control the persisted snapshot and app support directory.
- Suggested next step:
  - Include project IDs in the restored ID bump, add fixture guidance for stable IDs, and expose a test reset/seed path so E2E tests can start from known IDs in an isolated support directory.
- Fix-phase update: Restored project IDs now participate in `IDGen.bump`; XCTest seeds project `s99` and verifies the next created session is `s100`.
<!-- worker:persistence-fixtures:end -->

## UI And Accessibility Findings

<!-- worker:ui-accessibility:start -->
Readiness summary:

- Testable today: `swift build` from `macos/SacredTerminal` succeeds (`Build complete! (0.12s)`); the main window has a stable title (`The Sacred Terminal`); keyboard shortcuts exist for sidebar/browser/tabs/splits/new-session (`MainWindowController.handle`); the socket can `status`, `list-sessions`, `focus`, and `new-session`; quick-pick agent buttons and session-close buttons have some explicit Accessibility labels/identifiers.
- Not ready for selector-based UI smoke tests: several important controls are custom `NSView` mouse targets or image-only `NSButton`s without stable Accessibility roles/labels/identifiers, and several required flows depend on hover-only UI or native panels.
- Commands run for this section included `swift build`, `rg -n "setAccessibility(Label|Identifier)|accessibilityDescription|toolTip =|override func mouseDown|NSClickGestureRecognizer|isHidden = !hovering|acceptsHitTesting = hovering|func toggleBrowser|func split\\(|func addPane|func closePane|func closeSession|func createSession|case \\\"(status|list-sessions|focus|new-session)\\\"" macos/SacredTerminal/Sources/SacredTerminal`, `rg -n "stable Accessibility|quick-pick|session-close|needs click confirmation|needs visual confirmation|known issues|Menu-bar dropdown" macos/SacredTerminal/KNOWN_ISSUES.md macos/SacredTerminal/README.md`, and targeted `nl -ba ...` inspections of the AppKit view/controller files.

### UI-ACCESS-001: Custom View Controls Need Accessibility Roles And Actions

- Category: testability
- Severity: high
- Owner thread: worker:ui-accessibility
- Status: fixed for first UI smoke slice; remaining menu-bar/settings custom controls deferred
- Evidence: The source search above observed gesture/mouse-only controls in `Views/AgentPickerController.swift:284`, `Views/AgentPickerController.swift:363`, `Views/AgentPickerController.swift:369`, `MenuBar/MenuBarRoster.swift:173`, `MenuBar/MenuBarRoster.swift:236`, `Settings/SettingsWindowController.swift:1112`, `Settings/SettingsWindowController.swift:1157`, and `Settings/SettingsWindowController.swift:1210`. The same search only found explicit `setAccessibilityLabel` / `setAccessibilityIdentifier` calls in `Views/RailViewController.swift:426`, `Views/RailViewController.swift:427`, `Views/RailViewController.swift:511`, `Views/RailViewController.swift:617`, `Views/RailViewController.swift:618`, and `Views/RailViewController.swift:763`.
- Reproduction: Open the agent picker, menu-bar roster, or settings overlay and try to locate/invoke the worktree checkbox, agent picker rows, menu-bar session rows, settings tabs, settings switches, or checkbox rows through Accessibility selectors rather than coordinates. These controls are mostly `NSView` subclasses with `mouseDown` or `NSClickGestureRecognizer`, so the expected button/checkbox role and `performPress` action are not guaranteed.
- Suggested next step: Convert these controls to `NSButton`/`NSControl` where practical, or implement `NSAccessibility` role, label, identifier, value, and press action on `WorktreeCheckbox`, `AgentPickerRow`, `MenuBarSessionRow`, `MenuBarActionRow`, settings `TabButton`, `ToggleSwitch`, and `CheckBox`.
- Fix-phase update: Added Accessibility roles, labels, identifiers, and press actions for `ProjectRow`, `SessionRow`, `WorktreeCheckbox`, and `AgentPickerRow`. Follow-up fix converted session-row activation to a native transparent `NSButton` target so session rows are deterministic for both click handling and `AXPress`. Menu-bar roster rows and settings custom controls remain deferred because the first practical UI smoke path does not exercise them.

### UI-ACCESS-002: Workspace, Browser, And Titlebar Buttons Lack Stable Selectors

- Category: testability
- Severity: medium
- Owner thread: worker:ui-accessibility
- Status: fixed
- Evidence: `Views/RootViewController.swift:180`-`197` configures sidebar/browser image buttons with tooltip and symbol description only. `Views/WorkspaceViewController.swift:364`-`372` sets only `toolTip` for split/new-tab buttons; `Views/WorkspaceViewController.swift:581`-`588` creates tab buttons with empty titles; `Views/WorkspaceViewController.swift:611`-`628` gives tab close only a tooltip. `Browser/BrowserPanelController.swift:169`-`193` creates browser toolbar buttons with `accessibilityDescription: nil`, and the URL field at `Browser/BrowserPanelController.swift:83`-`99` has no identifier.
- Reproduction: After seeding a session, attempt to click `Toggle browser`, browser back/forward/reload/close, browser URL, `Split right`, `Split down`, `New tab`, pane tabs, or tab close through stable Accessibility identifiers. The visual controls exist, but automation would need fallback label guessing or coordinate clicks.
- Suggested next step: Add explicit identifiers and labels such as `titlebar-toggle-sidebar`, `titlebar-toggle-browser`, `workspace-split-right`, `workspace-split-down`, `workspace-new-tab`, `workspace-tab-<paneID>`, `workspace-tab-close-<paneID>`, `browser-url`, `browser-back`, `browser-forward`, `browser-reload`, and `browser-close`.
- Fix-phase update: Added stable labels/identifiers for the main window, titlebar sidebar/browser buttons, workspace split/new-tab/tab/close controls, browser panel/toolbar/back/forward/reload/URL/close controls, and rail settings/add-project buttons.

### UI-ACCESS-003: Hover-Only Session And Quick-Pick Controls Are Flaky Under Automation

- Category: flaky-risk
- Severity: high
- Owner thread: worker:ui-accessibility
- Status: deferred
- Evidence: `Views/RailViewController.swift:345`-`346` enables quick-pick hit testing and fades the pill only while hovering. `Views/RailViewController.swift:622` initially hides the session close button, and `Views/RailViewController.swift:692`-`694` only reveals it on hover. `Views/RailViewController.swift:718`-`744` uses `.assumeInside` tracking plus async pointer sync. `KNOWN_ISSUES.md:12`-`65` still marks quick-pick hover-grow, session close click, and adding a second session from the hover pill as needing visual/click confirmation.
- Reproduction: Hover a project row, click an agent, and immediately click another agent without moving the pointer; or hover a session row and click the revealed close button. These are exactly the flows future smoke tests want, but they depend on cursor position, animation timing, and view rebuilds.
- Suggested next step: Quarantine destructive/hover-only checks from the first smoke pass or add an E2E mode that disables animations and keeps hover affordances hit-testable/visible. Prefer direct Accessibility actions or socket/test commands for session creation and close assertions.
- Fix-phase update: The `RUN_UI_E2E=1` smoke test intentionally avoids hover-only quick-pick and session-close flows. It creates state through an isolated fixture, then drives deterministic new-tab and browser controls through Accessibility.

### UI-ACCESS-004: UI State Preconditioning Needs A Test Seam Beyond The Current Socket

- Category: testability
- Severity: high
- Owner thread: worker:ui-accessibility
- Status: fixed for first UI smoke slice; broader socket/test commands deferred
- Evidence: `State/AppState.swift:126`, `State/AppState.swift:140`, `State/AppState.swift:160`, `State/AppState.swift:169`, `State/AppState.swift:178`, and `State/AppState.swift:195` already contain state mutations for session creation/close, pane add/split/close, and browser toggle. The socket command search observed only `status`, `list-sessions`, `focus`, and `new-session` in `Socket/SocketServer.swift:228`-`248`; `new-session` requires an existing project ID. The clean empty-state path opens native folder selection at `Views/WorkspaceViewController.swift:203`-`214`, and rail add-project uses `NSMenu` / `NSOpenPanel` / `NSAlert` at `Views/RailViewController.swift:160`-`226`.
- Reproduction: Start with no persisted workspace and try to reach a deterministic state for tab/split/browser/menu-bar smoke tests without coordinate-clicking native panels or hand-editing persistence. There is no socket/test command to add a project, close a session, add/split/close panes, toggle browser, set browser URL, or force session status.
- Suggested next step: Add an E2E-only fixture loader or socket commands for add-project, close-session, add-pane, split, close-pane, toggle-browser, set-browser-url, and set-status. Keep product UI tests focused on a small number of user interactions after state is seeded.
- Fix-phase update: The UI E2E harness seeds a complete project/session snapshot in an isolated `SACRED_TERMINAL_APP_SUPPORT_DIR` before launching the real app. The smoke test verifies UI actions by reading the same isolated `session.json`; broader E2E-only socket commands for arbitrary UI state remain deferred.

### UI-ACCESS-005: Window Close/Reopen And Menu-Bar Snap-Back Need An Explicit Smoke Decision

- Category: question
- Severity: low
- Owner thread: worker:ui-accessibility
- Status: deferred
- Evidence: `AppDelegate.swift:49`-`57` intentionally keeps the app alive after the last window closes and reopens the main window on app reopen. `StatusItemController.swift:185`-`201` uses an `NSPopover` for the menu-bar roster and posts `.sacredFocusSession` when a row is picked. `MenuBarRoster.swift:88`-`195` implements session rows as custom gesture-backed `NSView`s, which is already covered as a testability gap in `UI-ACCESS-001`.
- Reproduction: Close the main window, assert sessions are still alive via `list-sessions`, then reopen/focus through Dock/app reopen or the menu-bar roster. This is a valuable product behavior, but menu-bar UI automation is likely brittle until roster rows have Accessibility roles/selectors.
- Suggested next step: Decide whether first-pass smoke tests cover only window close plus socket assertion, or also menu-bar snap-back. If snap-back is in scope, add Accessibility identifiers/actions to the status item and roster rows first.
- Fix-phase update: First-pass UI E2E scope is explicit: seeded window appears, titlebar/workspace controls are discoverable, new tab is clickable, and browser open/close is clickable. Window close/reopen and menu-bar snap-back remain deferred until roster rows have stable selectors/actions.
<!-- worker:ui-accessibility:end -->

## Known Broken And Quarantine Candidates

<!-- worker:known-broken:start -->
### KB-001: Hover-Only Rail Controls Need Manual/Opt-In UI Quarantine

- Category: known-broken, flaky-risk
- Severity: high
- Owner thread: worker:known-broken
- Status: deferred
- Evidence: `macos/SacredTerminal/KNOWN_ISSUES.md:12-65` explicitly marks quick-pick hover-grow, session close click, and adding a second session from the hover pill as needing visual/click confirmation. The implementation is still hover-gated: `RailViewController.ProjectRow.hoverChanged` only enables pill hit testing while hovering (`Sources/SacredTerminal/Views/RailViewController.swift:344-347`), quick-pick buttons fire sessions directly on mouse down (`RailViewController.swift:493-499`), and session close is hidden until hover (`RailViewController.swift:622`, `RailViewController.swift:692-694`). Command run: `nl -ba macos/SacredTerminal/KNOWN_ISSUES.md | sed -n '1,120p'`; observed lines include "needs visual confirmation", "needs click confirmation", and "needs click confirmation" for these three flows.
- Reproduction: Hover a project row, move across the agent icons, click an agent, then immediately click another agent without moving the pointer; or hover a session row and click the revealed `xmark`. These paths depend on cursor position, tracking-area sync, animations, and destructive state changes.
- Suggested next step: Keep these out of the first always-on pass. Put visual hover-grow and destructive close-click checks behind `RUN_UI_E2E` or mark them `XCTExpectFailure` until the manual pass lands. For always-on coverage, create sessions through fixture/socket state instead of the hover pill and avoid closing user/restored sessions.
- Fix-phase update: Still quarantined. The first UI smoke test does not automate hover-pill creation or hover-revealed session close; it uses fixture state plus non-hover titlebar/workspace/browser controls.

### KB-002: `sacred status` Is Flaky Under CLI Smoke Checks

- Category: known-broken, flaky-risk
- Severity: high
- Owner thread: worker:known-broken
- Status: fixed
- Evidence: `swift build` from `macos/SacredTerminal` succeeded (`Build complete! (0.13s)`), and the live socket itself responded to a raw probe:

  ```bash
  printf '{"cmd":"status"}\n' | nc -U "$HOME/Library/Application Support/SacredTerminal/control.sock"
  ```

  Observed output:

  ```text
  {"ok":true}
  ```

  `sacred ls` also succeeded and listed two live sessions. However repeated status CLI probes were inconsistent:

  ```bash
  for i in 1 2 3 4 5; do .build/arm64-apple-macosx/debug/sacred status; echo "code=$?"; done
  ```

  Observed equivalent captured output:

  ```text
  run1 code=0 stdout=The Sacred Terminal is running.|
  run2 code=141 stdout= stderr=
  run3 code=141 stdout= stderr=
  run4 code=141 stdout= stderr=
  run5 code=141 stdout= stderr=
  ```

  A mixed path probe also produced `code=141` for `.build/debug/sacred status` and `code=1 stderr=sacred: connection closed before a reply was received|` for `.build/arm64-apple-macosx/debug/sacred status`.
- Reproduction: With the app running and `control.sock` present, run `sacred status` repeatedly from `macos/SacredTerminal`. The socket may be healthy while the CLI exits via signal 13 (`141`) or reports EOF.
- Suggested next step: Quarantine `sacred status` as a harness readiness check for now. Prefer a raw socket `{"cmd":"status"}` probe or `sacred ls` only after the socket worker fixes/characterizes the status path. If kept in tests before the fix, wrap status assertions in `XCTExpectFailure`.
- Fix-phase update: Fixed by ignoring SIGPIPE in the CLI and making accepted app socket fds blocking before the server read loop starts. XCTest now runs repeated `sacred status` against an isolated launched app.

### KB-003: Programmable Browser API And Send-To-Agent Browser Clicks Are Not Implemented

- Category: known-broken, testability
- Severity: medium
- Owner thread: worker:known-broken
- Status: deferred
- Evidence: The spec promises browser socket actions (`browser snapshot`, `browser navigate`, `browser click`, `browser fill`, `browser eval`) plus console/network feedback and click-to-agent context (`docs/specs/spec.md:187-199`). The implemented socket dispatch only accepts `status`, `list-sessions`, `focus`, and `new-session` (`Sources/SacredTerminal/Socket/SocketServer.swift:227-251`). `BrowserPanelController` builds a local `WKWebView`, URL field, back/forward/reload, and close controls (`Sources/SacredTerminal/Browser/BrowserPanelController.swift:109-234`), but there is no script-message handler, accessibility-tree snapshot, socket browser command, console/network bridge, or send-to-agent click handler. Command run: `rg -n "browser snapshot|browser navigate|browser click|evaluateJavaScript|console|didReceive|case \"(status|list-sessions|focus|new-session)\"" macos/SacredTerminal/Sources/SacredTerminal docs/specs/spec.md`.
- Reproduction: Try to drive the browser through the documented socket-style commands or click page content expecting a ref/HTML/CSS/screenshot to be sent to the active agent. There is no command path or handler to observe.
- Suggested next step: First-pass E2E can smoke only browser pane open/close and maybe ordinary URL loading behind UI gating. Mark programmable browser, DOM/a11y snapshots, click/fill/eval, console/network streaming, and send-to-agent assertions as `XCTExpectFailure` or omit until a browser control API exists.

### KB-004: Worktree And Git/Source-Control Features Are UI/Model-Only

- Category: known-broken, question
- Severity: medium
- Owner thread: worker:known-broken
- Status: deferred
- Evidence: The picker exposes "Open with worktree" and passes `worktreeOn` into `AppState.createSession` (`Sources/SacredTerminal/Views/AgentPickerController.swift:137-189`), and `Session` persists `worktree` (`Sources/SacredTerminal/Models/Workspace.swift:29-50`). But terminal launch still uses the project path directly (`Sources/SacredTerminal/Views/WorkspaceViewController.swift:505-514`), `SocketServer.newSession` hard-codes `worktree: false` (`Sources/SacredTerminal/Socket/SocketServer.swift:278-284`), and the titlebar branch label is hard-coded to `⎇ main` (`Sources/SacredTerminal/Views/RootViewController.swift:138-142`). Git/source-control settings are persisted in `GitSettings` but no command path creates worktrees, renames branches, reads status, stages files, commits, or opens PRs (`Sources/SacredTerminal/State/AppState.swift:37-67`, `Sources/SacredTerminal/Settings/SettingsWindowController.swift:469-556`). Command run: `rg -n "worktree|branch|git|customCommand" macos/SacredTerminal/Sources/SacredTerminal docs/specs/spec.md`.
- Reproduction: Toggle "Open with worktree" when creating a session, or change Git settings, then inspect the launched terminal cwd/branch or app state. The flag/settings persist, but no filesystem/git operation is performed and the titlebar remains `main`.
- Suggested next step: Avoid E2E assertions for worktree creation/isolation, branch naming, Git status grouping, AI source-control actions, commit attribution, PR generation, or branch labels. Treat these as future product work unless product/design clarifies the intended first implementation.

### KB-005: Session Status Lifecycle Is Not Connected To Real Agent/PTY State

- Category: known-broken, testability
- Severity: medium
- Owner thread: worker:known-broken
- Status: deferred
- Evidence: The spec expects `working`, `waiting`, `done`, and `idle` to drive rail and menu-bar behavior (`docs/specs/spec.md:120-129`, `docs/specs/spec.md:161-175`). New non-shell sessions are initialized to `.working` and shell sessions to `.idle` (`Sources/SacredTerminal/State/AppState.swift:126-134`). There is a `setStatus` helper (`AppState.swift:146-148`), but the socket exposes no status mutation command (`SocketServer.swift:227-251`) and the libghostty close-surface callback is a no-op (`Sources/SacredTerminal/Ghostty/GhosttyBridge.swift:68-70`). Command run: `rg -n "setStatus|statusMeta|waiting|done|close_surface_cb|case \"(status|list-sessions|focus|new-session)\"" macos/SacredTerminal/Sources/SacredTerminal`.
- Reproduction: Start a real agent session and wait for it to finish or request input. The model has no implemented parser/callback path to flip from `working` to `waiting` or `done`, so rail/menu-bar status transitions are not deterministic.
- Suggested next step: For first-pass E2E, only assert initial status values from seeded fixtures or session creation. Mark live status transitions, waiting attention badges, done states, unread output, and menu-bar pulse changes from real PTY output as `XCTExpectFailure` until a deterministic status source or fixture command is added.

### KB-006: Hosted-Process Survival Across Quit/Relaunch Is Not Ready For Always-On E2E

- Category: known-broken, question
- Severity: medium
- Owner thread: worker:known-broken
- Status: deferred
- Evidence: The spec says every session runs in a long-lived host process independent of any window and that quitting/closing the window leaves sessions running (`docs/specs/spec.md:158-177`). The app prevents termination after the last window closes (`Sources/SacredTerminal/AppDelegate.swift:49-57`), but sessions are still created as `SurfaceView`/`GhosttySurface` instances owned by the window/workspace view tree (`Sources/SacredTerminal/Views/WorkspaceViewController.swift:18-45`, `Sources/SacredTerminal/Ghostty/SurfaceView.swift:39-55`). `GhosttySurface.free()` frees the libghostty surface (`Sources/SacredTerminal/Ghostty/GhosttyBridge.swift:178-184`), and there is no separate daemon/supervisor or reattach protocol in the source map beyond the app-local socket.
- Reproduction: Close-window behavior may be worth a manual smoke check, but full quit/relaunch and process reattachment cannot be proven from the current architecture because agent PTYs are not hosted outside the app process.
- Suggested next step: Keep first-pass always-on tests to non-destructive window close/reopen checks only if isolation is solved. Do not assert that real agent processes survive app quit/relaunch, daemon restarts, or reattach to previous PTYs until the hosted-process model is implemented or explicitly descoped.
- Fix-phase update: Running-app session switching no longer frees inactive terminal surfaces. `WorkspaceViewController` now retains pane hosts for all live sessions and only frees a surface after its pane disappears from workspace state; the opt-in UI E2E smoke logs surface init/free events and asserts that switching `s10 -> s12 -> s10` does not free either session's pane. Full app quit/relaunch survival remains deferred.
<!-- worker:known-broken:end -->

## Categorized Fix Queue

This section is owned by the orchestrator after worker findings are collected.

Fix-phase update (first E2E slice): landed the shared `SACRED_TERMINAL_APP_SUPPORT_DIR` app/CLI path seam, E2E-only fatal socket startup diagnostics, isolated SwiftPM black-box integration tests, fixture-safe Ghostty surface disabling, active-session/pane normalization, project-ID bumping, stale non-socket CLI handling, and repeated `sacred status` stability. Deferred items remain quarantined below: structured `--json` CLI output, multi-command socket framing, tolerant snapshot decoding, UI accessibility/smoke work, programmable browser, worktree/Git behavior, real agent status lifecycle, and hosted-process survival.

Fix-phase update (first UI E2E slice): landed minimal AppKit Accessibility selectors/actions and an opt-in `RUN_UI_E2E=1` XCTest. The test launches the real app with isolated fixture state, verifies seeded project/session/window controls, switches between two seeded sessions through the session-row selector, asserts inactive terminal surfaces are retained while switching sessions, presses `workspace-new-tab`, switches terminal tabs between the original and newly-created panes, opens the browser from the titlebar, verifies browser toolbar/URL selectors, closes the browser, and confirms persisted state changes in the isolated fixture. Remaining UI work below is limited to broader/custom surfaces such as menu-bar snap-back, settings, hover-only rail affordances, programmable browser APIs, and visual/pixel checks.

### Blockers

- Add an explicit app-support/socket isolation seam shared by the app and CLI.
  - Covers: HARN-ISO-001, HARN-ISO-002, PF-001, SC-001, SC-005.
  - Fix target: introduce one env var such as `SACRED_TERMINAL_APP_SUPPORT_DIR`; use it for `session.json` and `control.sock` in `Persistence`, `SocketServer`, and `sacred-cli`; make E2E tests use a per-test temp directory.
- Prevent E2E launches from restoring user sessions or spawning real user agent CLIs.
  - Covers: HARN-ISO-003, HARN-ISO-004.
  - Fix target: add deterministic E2E launch controls for state seeding, shell PATH, Ghostty config, and optionally disabling or replacing real Ghostty/agent surface startup for the first harness pass.
- Add a runnable SwiftPM test harness.
  - Covers: HARN-ISO-005.
  - Fix target: add a `Tests` target that black-box launches built products first; avoid large target refactors unless required.

### Product Bugs

- Socket startup failures are swallowed.
  - Covers: SC-002, HARN-ISO-002.
  - Fix target: log concrete bind/path failures and fail loudly in E2E mode when the control socket cannot start.
- Snapshot decoding is strict and silent.
  - Covers: PF-002.
  - Fix target: add tolerant decoders/defaults and diagnostics for old or partial snapshots.
- Restored active session/pane state is not normalized.
  - Covers: PF-003.
  - Fix target: validate `activeSessionID`, ensure every session has a pane, and ensure `activePaneID` exists after loading.
- Project IDs are excluded from restored ID bumping.
  - Covers: PF-004.
  - Fix target: include project IDs in `IDGen.bump` and add regression coverage.
- `sacred status` can be flaky under repeated CLI smoke checks.
  - Covers: KB-002.
  - Fix target: characterize/fix EOF/SIGPIPE behavior; prefer raw socket `status` or `sacred ls` until fixed.

### Testability Work

- Add positive socket/CLI E2E tests only after isolated fixtures exist.
  - Covers: SC-004, SC-005.
  - Suggested scope: `status`, `ls`, `new`, `focus`, malformed JSON, unknown command, missing fields, stale socket/non-socket path.
- Add structured machine-readable CLI output.
  - Covers: SC-004.
  - Fix target: add `--json` and stable server error codes.
- Decide and document socket protocol framing.
  - Covers: SC-003.
  - Fix target: either document one request per connection or process multiple JSON lines per connection.
- Add deterministic UI state preconditioning.
  - Covers: UI-ACCESS-004.
  - Fix target: fixture loader or E2E-only socket commands for add project, close session, panes/splits, browser URL/open state, and status.
  - Status update: fixed for the first UI smoke path via isolated fixture snapshots; broader E2E-only state commands remain deferred.
- Add Accessibility roles, identifiers, and actions for UI smoke paths.
  - Covers: UI-ACCESS-001, UI-ACCESS-002, UI-ACCESS-005.
  - Fix target: custom controls need roles/actions; titlebar/workspace/browser/menu-bar controls need stable identifiers.
  - Status update: fixed for main-window/titlebar/workspace/browser/project/session/agent-picker first-slice controls; menu-bar/settings custom controls remain deferred.
- Add deterministic E2E env controls for shell/Ghostty behavior.
  - Covers: HARN-ISO-004.
  - Fix target: skip login-shell PATH import in E2E mode and force temp Ghostty config/theme.

### Flaky Risks

- Socket path unlink/stale path behavior can disrupt live app state without isolation.
  - Covers: HARN-ISO-002, SC-007.
- Empty socket frames return EOF instead of structured JSON.
  - Covers: SC-006.
- Hover-only quick-pick/session-close flows are animation and pointer-position sensitive.
  - Covers: UI-ACCESS-003, KB-001.
- Generated IDs depend on restored fixtures and process order.
  - Covers: PF-004.
- Menu-bar snap-back and window close/reopen need a narrow smoke scope before UI automation.
  - Covers: UI-ACCESS-005, KB-006.

### Known Broken / Quarantined

- Quarantine hover-only rail checks from always-on E2E.
  - Covers: KB-001, UI-ACCESS-003.
- Quarantine programmable browser assertions.
  - Covers: KB-003.
  - Allowed first-pass scope: open/close browser pane and URL toolbar selectors; this is now covered by the opt-in UI smoke. Programmable DOM/click/fill/eval assertions remain quarantined.
- Quarantine worktree and Git/source-control behavior.
  - Covers: KB-004.
- Quarantine real agent status lifecycle transitions.
  - Covers: KB-005.
  - Allowed first-pass scope: assert initial statuses from fixtures or deterministic session creation.
- Quarantine hosted-process survival across full app quit/relaunch.
  - Covers: KB-006.
  - Allowed first-pass scope: window close/reopen only, after isolation is solved.

### Open Questions

- Should the socket remain one-command-per-connection, or become true newline-delimited streaming?
- What env var name should be canonical for isolated app support: `SACRED_TERMINAL_APP_SUPPORT_DIR`, `SACREDTERMINAL_APP_SUPPORT_DIR`, or a separate socket/session pair?
- Should first-pass UI smoke include menu-bar snap-back, or stop at window close plus socket assertion?
- Should E2E mode disable Ghostty surface creation entirely, or launch a deterministic shell/script surface?
- Are worktree/Git/source-control features in scope for this E2E milestone or explicitly future product work?
