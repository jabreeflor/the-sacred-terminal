import ApplicationServices
import Darwin
import Foundation
import SacredTerminalSupport
import XCTest

final class SacredTerminalIntegrationTests: XCTestCase {
    private static let buildLock = NSLock()
    private static var didBuildProducts = false

    private var tempDirs: [URL] = []

    override func setUpWithError() throws {
        signal(SIGPIPE, SIG_IGN)
        try Self.buildProductsIfNeeded()
    }

    override func tearDownWithError() throws {
        for dir in tempDirs.reversed() {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func testIsolatedStatusReportsNotRunningWhenNoAppOwnsSocket() throws {
        let supportDir = try makeTempDirectory()

        let result = try runSacred(["status"], supportDir: supportDir)

        XCTAssertEqual(result.terminationStatus, 1)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "The Sacred Terminal is not running.")
        XCTAssertEqual(result.stderr, "")
    }

    func testRegularFileAtControlPathIsTreatedAsNotRunning() throws {
        let supportDir = try makeTempDirectory()
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try Data("not a socket".utf8).write(to: supportDir.appendingPathComponent("control.sock"))

        let result = try runSacred(["status"], supportDir: supportDir)

        XCTAssertEqual(result.terminationStatus, 1)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "The Sacred Terminal is not running.")
        XCTAssertEqual(result.stderr, "")
    }

    func testRawSocketProtocolReportsStatusAndStructuredErrors() throws {
        let supportDir = try makeTempDirectory()
        let app = try launchApp(supportDir: supportDir)
        defer { app.terminate() }

        let socketPath = supportDir.appendingPathComponent("control.sock").path

        let malformed = try rawSocketJSON(socketPath: socketPath, line: "not-json\n")
        XCTAssertEqual(malformed["ok"] as? Bool, false)
        XCTAssertEqual(malformed["error"] as? String, "invalid JSON")

        let missingCommand = try rawSocketJSON(socketPath: socketPath, line: "{}\n")
        XCTAssertEqual(missingCommand["ok"] as? Bool, false)
        XCTAssertEqual(missingCommand["error"] as? String, "missing \"cmd\"")

        let unknown = try rawSocketJSON(socketPath: socketPath, object: ["cmd": "bogus"])
        XCTAssertEqual(unknown["ok"] as? Bool, false)
        XCTAssertEqual(unknown["error"] as? String, "unknown cmd \"bogus\"")

        let status = try rawSocketJSON(socketPath: socketPath, object: ["cmd": "status"])
        XCTAssertEqual(status["ok"] as? Bool, true)
    }

    func testSacredStatusIsStableAgainstLaunchedIsolatedApp() throws {
        let supportDir = try makeTempDirectory()
        let app = try launchApp(supportDir: supportDir)
        defer { app.terminate() }

        for _ in 0..<5 {
            let result = try runSacred(["status"], supportDir: supportDir)
            XCTAssertEqual(result.terminationStatus, 0)
            XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                           "The Sacred Terminal is running.")
            XCTAssertEqual(result.stderr, "")
        }
    }

    func testSeededFixtureSupportsListFocusAndNewSession() throws {
        let supportDir = try makeTempDirectory()
        let projectDir = try makeTempDirectory(prefix: "st-e2e-project")
        try writeFixtureSnapshot(supportDir: supportDir, projectPath: projectDir)

        let app = try launchApp(supportDir: supportDir)
        defer { app.terminate() }

        let initialList = try runSacred(["ls"], supportDir: supportDir)
        XCTAssertEqual(initialList.terminationStatus, 0)
        XCTAssertTrue(initialList.stdout.contains("s10"))
        XCTAssertTrue(initialList.stdout.contains("Fixture Project"))
        XCTAssertTrue(initialList.stdout.contains("shell"))
        XCTAssertTrue(initialList.stdout.contains("idle"))

        let focus = try runSacred(["focus", "s10"], supportDir: supportDir)
        XCTAssertEqual(focus.terminationStatus, 0)
        XCTAssertEqual(focus.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Focused session s10.")

        let created = try runSacred(["new", "s99", "shell"], supportDir: supportDir)
        XCTAssertEqual(created.terminationStatus, 0)
        XCTAssertTrue(created.stdout.contains("Created session s100"),
                      "Expected project id s99 to bump the generated session id; got: \(created.stdout)")

        let finalList = try runSacred(["ls"], supportDir: supportDir)
        XCTAssertEqual(finalList.terminationStatus, 0)
        XCTAssertTrue(finalList.stdout.contains("s10"))
        XCTAssertTrue(finalList.stdout.contains("s100"))

        let snapshotData = try Data(contentsOf: supportDir.appendingPathComponent("session.json"))
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        let projects = try XCTUnwrap(snapshot["projects"] as? [[String: Any]])
        let sessions = try XCTUnwrap(projects.first?["sessions"] as? [[String: Any]])
        let firstSession = try XCTUnwrap(sessions.first(where: { ($0["id"] as? String) == "s10" }))
        XCTAssertEqual(firstSession["activePaneID"] as? String, "s11")
    }

    func testMCPListsToolsAndMapsCallsToAppState() throws {
        let supportDir = try makeTempDirectory()
        let projectDir = try makeTempDirectory(prefix: "st-e2e-mcp-project")
        try writeFixtureSnapshot(supportDir: supportDir, projectPath: projectDir)

        let app = try launchApp(supportDir: supportDir)
        defer { app.terminate() }

        let responses = try runSacredMCP([
            [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": [
                    "protocolVersion": "2025-03-26",
                    "capabilities": [:],
                    "clientInfo": ["name": "SacredTerminalIntegrationTests", "version": "1.0"],
                ],
            ],
            [
                "jsonrpc": "2.0",
                "method": "notifications/initialized",
            ],
            [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/list",
                "params": [:],
            ],
            [
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": [
                    "name": "sacred_create_session",
                    "arguments": ["project_id": "s99", "agent": "shell"],
                ],
            ],
            [
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": [
                    "name": "sacred_focus_session",
                    "arguments": ["session_id": "s10"],
                ],
            ],
            [
                "jsonrpc": "2.0",
                "id": 5,
                "method": "tools/call",
                "params": [
                    "name": "sacred_toggle_browser",
                    "arguments": ["session_id": "s10", "open": true],
                ],
            ],
        ], supportDir: supportDir)

        let initialize = try mcpResponse(responses, id: 1)
        let initializeResult = try XCTUnwrap(initialize["result"] as? [String: Any])
        XCTAssertEqual(initializeResult["protocolVersion"] as? String, "2025-03-26")

        let toolsList = try mcpResponse(responses, id: 2)
        let toolsResult = try XCTUnwrap(toolsList["result"] as? [String: Any])
        let toolNames = try XCTUnwrap(toolsResult["tools"] as? [[String: Any]]).compactMap { $0["name"] as? String }
        XCTAssertTrue(toolNames.contains("sacred_create_session"))
        XCTAssertTrue(toolNames.contains("sacred_toggle_browser"))

        for id in [3, 4, 5] {
            let call = try mcpResponse(responses, id: id)
            let result = try XCTUnwrap(call["result"] as? [String: Any])
            XCTAssertEqual(result["isError"] as? Bool, false, "MCP call \(id) failed: \(result)")
        }

        let snapshot = try fixtureSnapshot(supportDir: supportDir)
        XCTAssertEqual(snapshot["activeSessionID"] as? String, "s10")
        let projects = try XCTUnwrap(snapshot["projects"] as? [[String: Any]])
        let sessions = try XCTUnwrap(projects.first?["sessions"] as? [[String: Any]])
        XCTAssertTrue(sessions.contains(where: { ($0["id"] as? String) == "s100" }))
        let firstSession = try XCTUnwrap(sessions.first(where: { ($0["id"] as? String) == "s10" }))
        XCTAssertEqual(firstSession["browserOpen"] as? Bool, true)
    }

    func testE2ESocketStartupFailureExitsAppWithDiagnostic() throws {
        let longName = "st-e2e-long-" + String(repeating: "x", count: 92)
        let supportDir = URL(fileURLWithPath: "/tmp").appendingPathComponent(longName, isDirectory: true)
        try? FileManager.default.removeItem(at: supportDir)
        tempDirs.append(supportDir)

        let result = try Self.runProcess(Self.appExecutableURL(),
                                         environment: e2eEnvironment(supportDir: supportDir),
                                         timeout: 10)

        XCTAssertNotEqual(result.terminationStatus, 0)
        XCTAssertTrue(result.stderr.contains("socket startup failed"),
                      "Expected socket startup diagnostic in stderr; got: \(result.stderr)")
        XCTAssertTrue(result.stderr.contains("socket path too long"),
                      "Expected AF_UNIX path-length diagnostic in stderr; got: \(result.stderr)")
    }

    func testUIE2ESmokeTogglesBrowserPaneThroughAccessibility() throws {
        try requireUIE2EEnabled()
        try requireAccessibilityTrust()

        let supportDir = try makeTempDirectory()
        let projectDir = try makeTempDirectory(prefix: "st-e2e-ui-project")
        try writeFixtureSnapshot(supportDir: supportDir,
                                 projectPath: projectDir,
                                 collapsed: false,
                                 includeSecondSession: true)
        let surfaceEventsLog = supportDir.appendingPathComponent("surface-events.log")

        let app = try launchApp(supportDir: supportDir,
                                extraEnvironment: [
                                    "SACRED_TERMINAL_SURFACE_EVENTS_LOG": surfaceEventsLog.path,
                                ])
        defer { app.terminate() }

        let axApp = AXUIElementCreateApplication(app.process.processIdentifier)
        _ = try waitForAXWindow(in: axApp, title: "The Sacred Terminal", timeout: 10)
        _ = try waitForAXElement(in: axApp, identifier: "titlebar-toggle-sidebar", timeout: 5)
        let browserToggle = try waitForAXElement(in: axApp, identifier: "titlebar-toggle-browser", timeout: 5)
        _ = try waitForAXElement(in: axApp, identifier: "project-row-s99", timeout: 5)
        _ = try waitForAXElement(in: axApp, identifier: "session-row-s10", timeout: 5)
        let secondSession = try waitForAXElement(in: axApp, identifier: "session-row-s12", timeout: 5)
        _ = try waitForAXElement(in: axApp, identifier: "workspace-split-right", timeout: 5)
        _ = try waitForAXElement(in: axApp, identifier: "workspace-split-down", timeout: 5)

        try pressAXElement(secondSession, identifier: "session-row-s12")
        try waitUntil("second session became active from Accessibility press") {
            try fixtureActiveSessionID(supportDir: supportDir) == "s12"
        }
        let firstSession = try waitForAXElement(in: axApp, identifier: "session-row-s10", timeout: 5)
        try pressAXElement(firstSession, identifier: "session-row-s10")
        try waitUntil("first session became active from Accessibility press") {
            try fixtureActiveSessionID(supportDir: supportDir) == "s10"
        }
        try assertSurfaceEventsRetainedAcrossSessionSwitch(surfaceEventsLog)

        let newTab = try waitForAXElement(in: axApp, identifier: "workspace-new-tab", timeout: 5)
        try pressAXElement(newTab, identifier: "workspace-new-tab")
        try waitUntil("new tab persisted to the isolated fixture") {
            try fixturePaneIDs(supportDir: supportDir).count == 2
        }
        try waitUntil("new tab became the active terminal pane") {
            try fixtureActivePaneID(supportDir: supportDir) == "s100"
        }
        let firstTerminalTab = try waitForAXElement(in: axApp, identifier: "workspace-tab-s11", timeout: 5)
        _ = try waitForAXElement(in: axApp, identifier: "workspace-tab-s100", timeout: 5)

        try pressAXElement(firstTerminalTab, identifier: "workspace-tab-s11")
        try waitUntil("first terminal tab became active from Accessibility press") {
            try fixtureActivePaneID(supportDir: supportDir) == "s11"
        }
        let newTerminalTab = try waitForAXElement(in: axApp, identifier: "workspace-tab-s100", timeout: 5)
        try pressAXElement(newTerminalTab, identifier: "workspace-tab-s100")
        try waitUntil("new terminal tab became active from Accessibility press") {
            try fixtureActivePaneID(supportDir: supportDir) == "s100"
        }

        try pressAXElement(browserToggle, identifier: "titlebar-toggle-browser")
        try waitUntil("browser open state persisted to the isolated fixture") {
            try fixtureBrowserOpen(supportDir: supportDir) == true
        }
        let urlField = try waitForAXElement(in: axApp, identifier: "browser-url", timeout: 5)
        XCTAssertEqual(axStringAttribute(urlField, Self.axValueAttribute), "http://localhost:3000")
        _ = try waitForAXElement(in: axApp, identifier: "browser-reload", timeout: 5)

        let closeBrowser = try waitForAXElement(in: axApp, identifier: "browser-close", timeout: 5)
        try pressAXElement(closeBrowser, identifier: "browser-close")
        try waitUntil("browser closed state persisted to the isolated fixture") {
            try fixtureBrowserOpen(supportDir: supportDir) == false
        }
        try waitUntil("browser toolbar disappeared from the accessibility tree") {
            !isAXElementPresent(in: axApp, identifier: "browser-url")
        }
    }

    private func runSacred(_ arguments: [String], supportDir: URL) throws -> ProcessResult {
        try Self.runProcess(Self.sacredExecutableURL(),
                            arguments: arguments,
                            environment: [
                                SacredTerminalRuntime.appSupportDirectoryEnv: supportDir.path,
                            ],
                            timeout: 10)
    }

    private func runSacredMCP(_ messages: [[String: Any]], supportDir: URL) throws -> [[String: Any]] {
        let process = Process()
        process.executableURL = try Self.mcpExecutableURL()
        process.currentDirectoryURL = Self.packageRoot
        process.environment = Self.mergedEnvironment([
            SacredTerminalRuntime.appSupportDirectoryEnv: supportDir.path,
        ])

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        for message in messages {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            stdin.fileHandleForWriting.write(data)
        }
        stdin.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.3)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw IntegrationTestError.processTimedOut("sacred-mcp timed out")
        }

        process.waitUntilExit()
        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw IntegrationTestError.processFailed("sacred-mcp exited \(process.terminationStatus): \(stderrText)")
        }
        XCTAssertEqual(stderrText, "")

        return try stdoutText
            .split(separator: "\n")
            .map { line in
                let data = Data(line.utf8)
                guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw IntegrationTestError.processFailed("MCP response was not an object: \(line)")
                }
                return response
            }
    }

    private func launchApp(supportDir: URL,
                           extraEnvironment: [String: String] = [:]) throws -> RunningApp {
        let process = Process()
        process.executableURL = try Self.appExecutableURL()
        process.arguments = []
        process.currentDirectoryURL = Self.packageRoot
        var environment = e2eEnvironment(supportDir: supportDir)
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = Self.mergedEnvironment(environment)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let app = RunningApp(process: process, stdout: stdout, stderr: stderr)
        do {
            try waitForSocket(process: process,
                              socketPath: supportDir.appendingPathComponent("control.sock").path,
                              stderr: stderr,
                              timeout: 10)
            return app
        } catch {
            app.terminate()
            throw error
        }
    }

    private func waitForSocket(process: Process,
                               socketPath: String,
                               stderr: Pipe,
                               timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !process.isRunning {
                let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                                        encoding: .utf8) ?? ""
                throw IntegrationTestError.processFailed("app exited before socket was ready: \(stderrText)")
            }

            if FileManager.default.fileExists(atPath: socketPath),
               let reply = try? rawSocketJSON(socketPath: socketPath, object: ["cmd": "status"]),
               (reply["ok"] as? Bool) == true {
                return
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        throw IntegrationTestError.processTimedOut("app did not open \(socketPath) within \(timeout)s")
    }

    private func e2eEnvironment(supportDir: URL) -> [String: String] {
        [
            SacredTerminalRuntime.appSupportDirectoryEnv: supportDir.path,
            SacredTerminalRuntime.e2eModeEnv: "1",
            SacredTerminalRuntime.disableGhosttySurfacesEnv: "1",
            SacredTerminalRuntime.skipShellPathImportEnv: "1",
            "HOME": supportDir.appendingPathComponent("home", isDirectory: true).path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "SHELL": "/bin/zsh",
        ]
    }

    private func writeFixtureSnapshot(supportDir: URL,
                                      projectPath: URL,
                                      collapsed: Bool = true,
                                      includeSecondSession: Bool = false) throws {
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        var sessions: [[String: Any]] = [
            [
                "id": "s10",
                "agent": "shell",
                "task": "zsh",
                "status": "idle",
                "worktree": false,
                "yolo": false,
                "browserOpen": false,
                "browserURL": "http://localhost:3000",
                "panes": [
                    [
                        "id": "s11",
                        "title": "shell",
                        "kind": "shell",
                        "started": false,
                    ],
                ],
                "activePaneID": "missing-pane",
                "splitLayout": "none",
            ],
        ]
        if includeSecondSession {
            sessions.append([
                "id": "s12",
                "agent": "gemini",
                "task": "New Gemini session",
                "status": "working",
                "worktree": false,
                "yolo": false,
                "browserOpen": false,
                "browserURL": "http://localhost:3000",
                "panes": [
                    [
                        "id": "s13",
                        "title": "Gemini",
                        "kind": "agent",
                        "started": false,
                    ],
                ],
                "activePaneID": "s13",
                "splitLayout": "none",
            ])
        }

        let snapshot: [String: Any] = [
            "activeSessionID": "missing-session",
            "agentEnabled": ["claude", "codex", "cursor", "gemini", "copilot", "opencode", "shell"],
            "agentSettings": ["openWithYolo": false],
            "appearance": [
                "ghosttyTheme": "catppuccin-frappe",
                "railWidth": "standard",
                "railBg": "#0a0a0c",
                "railFg": "#e6e6ea",
                "sessionHighlight": "#fab387",
            ],
            "git": [
                "branchPrefix": "git",
                "customPrefix": "",
                "autoRenameBranch": true,
                "commitAttribution": false,
                "keepMainUpdated": false,
                "draftByDefault": false,
                "scGroupOrder": "changes",
                "showScAiActions": true,
                "customCommand": "",
                "usePrTemplate": true,
                "generatePrOnOpen": false,
                "openPrAfterCreate": false,
            ],
            "pinnedAgents": ["opencode", "cursor", "gemini", "codex", "claude"],
            "projects": [
                [
                    "id": "s99",
                    "name": "Fixture Project",
                    "path": projectPath.path,
                    "collapsed": collapsed,
                    "sessions": sessions,
                ],
            ],
            "sidebarOpen": true,
        ]

        let data = try JSONSerialization.data(withJSONObject: snapshot,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: supportDir.appendingPathComponent("session.json"), options: .atomic)
    }

    private func requireUIE2EEnabled() throws {
        guard Self.truthyEnvironmentValue("RUN_UI_E2E") else {
            throw XCTSkip("Set RUN_UI_E2E=1 to run the AppKit Accessibility UI E2E smoke test.")
        }
    }

    private func requireAccessibilityTrust() throws {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: false] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw XCTSkip("""
            RUN_UI_E2E=1 requires macOS Accessibility permission for the process running `swift test` \
            (Terminal, Codex, or the XCTest runner). Grant it in System Settings > Privacy & Security > Accessibility.
            """)
        }
    }

    private func fixturePaneIDs(supportDir: URL) throws -> [String] {
        let session = try fixtureSession(supportDir: supportDir)
        let panes = try XCTUnwrap(session["panes"] as? [[String: Any]])
        return panes.compactMap { $0["id"] as? String }
    }

    private func assertSurfaceEventsRetainedAcrossSessionSwitch(_ logURL: URL) throws {
        let lines = try surfaceEventLines(logURL)
        XCTAssertEqual(lines.filter { $0 == "init session=s10 pane=s11" }.count, 1)
        XCTAssertEqual(lines.filter { $0 == "init session=s12 pane=s13" }.count, 1)
        XCTAssertFalse(lines.contains("free session=s10 pane=s11"),
                       "Switching away from s10 should not free its terminal surface. Events: \(lines)")
        XCTAssertFalse(lines.contains("free session=s12 pane=s13"),
                       "Switching away from s12 should not free its terminal surface. Events: \(lines)")
    }

    private func surfaceEventLines(_ logURL: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        let text = try String(contentsOf: logURL, encoding: .utf8)
        return text.split(separator: "\n").map(String.init)
    }

    private func fixtureActivePaneID(supportDir: URL) throws -> String {
        let session = try fixtureSession(supportDir: supportDir)
        return try XCTUnwrap(session["activePaneID"] as? String)
    }

    private func fixtureBrowserOpen(supportDir: URL) throws -> Bool {
        let session = try fixtureSession(supportDir: supportDir)
        return try XCTUnwrap(session["browserOpen"] as? Bool)
    }

    private func fixtureActiveSessionID(supportDir: URL) throws -> String {
        let snapshot = try fixtureSnapshot(supportDir: supportDir)
        return try XCTUnwrap(snapshot["activeSessionID"] as? String)
    }

    private func fixtureSession(supportDir: URL) throws -> [String: Any] {
        let snapshot = try fixtureSnapshot(supportDir: supportDir)
        let projects = try XCTUnwrap(snapshot["projects"] as? [[String: Any]])
        let sessions = try XCTUnwrap(projects.first?["sessions"] as? [[String: Any]])
        return try XCTUnwrap(sessions.first(where: { ($0["id"] as? String) == "s10" }))
    }

    private func fixtureSnapshot(supportDir: URL) throws -> [String: Any] {
        let snapshotData = try Data(contentsOf: supportDir.appendingPathComponent("session.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
    }

    private func mcpResponse(_ responses: [[String: Any]], id: Int) throws -> [String: Any] {
        try XCTUnwrap(responses.first { response in
            if let value = response["id"] as? Int {
                return value == id
            }
            if let value = response["id"] as? NSNumber {
                return value.intValue == id
            }
            return false
        }, "Missing MCP response id \(id). Responses: \(responses)")
    }

    private func rawSocketJSON(socketPath: String, object: [String: Any]) throws -> [String: Any] {
        var data = try JSONSerialization.data(withJSONObject: object, options: [])
        data.append(0x0A)
        return try rawSocketJSON(socketPath: socketPath, line: String(decoding: data, as: UTF8.self))
    }

    private func rawSocketJSON(socketPath: String, line: String) throws -> [String: Any] {
        let reply = try rawSocketLine(socketPath: socketPath, line: line)
        let data = Data(reply.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationTestError.socket("reply was not a JSON object: \(reply)")
        }
        return object
    }

    private func rawSocketLine(socketPath: String, line: String) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IntegrationTestError.socket("socket() failed: \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < capacity else {
            throw IntegrationTestError.socket("socket path too long: \(socketPath)")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                for (index, byte) in pathBytes.enumerated() {
                    dst[index] = CChar(bitPattern: byte)
                }
                dst[pathBytes.count] = 0
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw IntegrationTestError.socket("connect(\(socketPath)) failed: \(String(cString: strerror(errno)))")
        }

        try writeAll(fd: fd, data: Data(line.utf8))

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = chunk.withUnsafeMutableBytes { raw in
                read(fd, raw.baseAddress, raw.count)
            }
            if count == 0 {
                break
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw IntegrationTestError.socket("read failed: \(String(cString: strerror(errno)))")
            }
            buffer.append(contentsOf: chunk[0..<count])
            if let newline = buffer.firstIndex(of: 0x0A) {
                buffer = buffer.subdata(in: buffer.startIndex..<newline)
                break
            }
        }

        if buffer.last == 0x0D {
            buffer = buffer.dropLast()
        }
        return String(decoding: buffer, as: UTF8.self)
    }

    private func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(fd, base.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw IntegrationTestError.socket("write failed: \(String(cString: strerror(errno)))")
                }
                if written == 0 {
                    throw IntegrationTestError.socket("write returned 0")
                }
                offset += written
            }
        }
    }

    private func makeTempDirectory(prefix: String = "st-e2e") throws -> URL {
        var template = Array("/tmp/\(prefix).XXXXXX".utf8CString)
        let path = template.withUnsafeMutableBufferPointer { buffer -> UnsafeMutablePointer<CChar>? in
            guard let base = buffer.baseAddress else { return nil }
            return mkdtemp(base)
        }
        guard let path else {
            throw IntegrationTestError.socket("mkdtemp failed: \(String(cString: strerror(errno)))")
        }
        let url = URL(fileURLWithPath: String(cString: path), isDirectory: true)
        tempDirs.append(url)
        return url
    }

    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 5,
                           _ condition: () throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            do {
                if try condition() { return }
            } catch {
                lastError = error
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if let lastError {
            throw IntegrationTestError.processTimedOut("\(description) timed out after \(timeout)s: \(lastError)")
        }
        throw IntegrationTestError.processTimedOut("\(description) timed out after \(timeout)s")
    }

    private func waitForAXWindow(in app: AXUIElement,
                                 title: String,
                                 timeout: TimeInterval) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let window = axElement(in: app, matching: { element in
                axStringAttribute(element, Self.axTitleAttribute) == title
            }) {
                return window
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw IntegrationTestError.processTimedOut("AX window titled \(title) did not appear within \(timeout)s")
    }

    private func waitForAXElement(in root: AXUIElement,
                                  identifier: String,
                                  timeout: TimeInterval) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = axElement(in: root, identifier: identifier) {
                return element
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw IntegrationTestError.processTimedOut("AX element \(identifier) did not appear within \(timeout)s")
    }

    private func isAXElementPresent(in root: AXUIElement, identifier: String) -> Bool {
        axElement(in: root, identifier: identifier) != nil
    }

    private func pressAXElement(_ element: AXUIElement, identifier: String) throws {
        let error = AXUIElementPerformAction(element, Self.axPressAction)
        guard error == .success else {
            throw IntegrationTestError.processFailed("AXPress failed for \(identifier): \(error)")
        }
    }

    private func axElement(in root: AXUIElement, identifier: String) -> AXUIElement? {
        axElement(in: root) { element in
            axStringAttribute(element, Self.axIdentifierAttribute) == identifier
        }
    }

    private func axElement(in root: AXUIElement,
                           matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        var stack = [root]
        var visited = Set<CFHashCode>()
        var scanned = 0

        while let element = stack.popLast(), scanned < 4_000 {
            scanned += 1
            let hash = CFHash(element)
            guard visited.insert(hash).inserted else { continue }

            if predicate(element) {
                return element
            }

            for attribute in Self.axDescendantAttributes {
                stack.append(contentsOf: axElementArray(element, attribute))
            }
        }

        return nil
    }

    private func axElementArray(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return []
        }
        guard let array = value as? [Any] else {
            return []
        }
        return array.map { $0 as! AXUIElement }
    }

    private func axStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static var packageRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }()

    private static func buildProductsIfNeeded() throws {
        buildLock.lock()
        defer { buildLock.unlock() }

        guard !didBuildProducts else { return }

        _ = try productURL(named: "sacred")
        _ = try productURL(named: "sacred-mcp")
        _ = try productURL(named: "SacredTerminal")

        didBuildProducts = true
    }

    private static func sacredExecutableURL() throws -> URL {
        try productURL(named: "sacred")
    }

    private static func appExecutableURL() throws -> URL {
        try productURL(named: "SacredTerminal")
    }

    private static func mcpExecutableURL() throws -> URL {
        try productURL(named: "sacred-mcp")
    }

    private static func productURL(named name: String) throws -> URL {
        let candidates = [
            packageRoot.appendingPathComponent(".build/debug/\(name)"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/\(name)"),
            packageRoot.appendingPathComponent(".build/x86_64-apple-macosx/debug/\(name)"),
        ]
        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return match
        }
        throw IntegrationTestError.processFailed("could not find built product \(name)")
    }

    private static func runProcess(_ executable: URL,
                                   arguments: [String] = [],
                                   currentDirectory: URL? = nil,
                                   environment: [String: String] = [:],
                                   timeout: TimeInterval) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory ?? packageRoot
        process.environment = mergedEnvironment(environment)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.3)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw IntegrationTestError.processTimedOut("\(executable.path) timed out after \(timeout)s")
        }

        process.waitUntilExit()
        return ProcessResult(terminationStatus: process.terminationStatus,
                             stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(),
                                            encoding: .utf8) ?? "",
                             stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                                            encoding: .utf8) ?? "")
    }

    private static func mergedEnvironment(_ overrides: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in overrides {
            environment[key] = value
        }
        return environment
    }

    private static func truthyEnvironmentValue(_ key: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return false
        }
        return !["0", "false", "no", "off"].contains(raw.lowercased())
    }

    private static let axIdentifierAttribute = "AXIdentifier" as CFString
    private static let axTitleAttribute = "AXTitle" as CFString
    private static let axValueAttribute = "AXValue" as CFString
    private static let axPressAction = "AXPress" as CFString
    private static let axDescendantAttributes = [
        "AXWindows" as CFString,
        "AXChildren" as CFString,
        "AXContents" as CFString,
    ]
}

private struct ProcessResult {
    let terminationStatus: Int32
    let stdout: String
    let stderr: String
}

private struct RunningApp {
    let process: Process
    let stdout: Pipe
    let stderr: Pipe

    func terminate() {
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.3)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        _ = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
    }
}

private enum IntegrationTestError: Error, CustomStringConvertible {
    case processFailed(String)
    case processTimedOut(String)
    case socket(String)

    var description: String {
        switch self {
        case .processFailed(let message), .processTimedOut(let message), .socket(let message):
            return message
        }
    }
}
