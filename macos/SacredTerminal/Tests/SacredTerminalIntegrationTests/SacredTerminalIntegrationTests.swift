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

    private func runSacred(_ arguments: [String], supportDir: URL) throws -> ProcessResult {
        try Self.runProcess(Self.sacredExecutableURL(),
                            arguments: arguments,
                            environment: [
                                SacredTerminalRuntime.appSupportDirectoryEnv: supportDir.path,
                            ],
                            timeout: 10)
    }

    private func launchApp(supportDir: URL) throws -> RunningApp {
        let process = Process()
        process.executableURL = try Self.appExecutableURL()
        process.arguments = []
        process.currentDirectoryURL = Self.packageRoot
        process.environment = Self.mergedEnvironment(e2eEnvironment(supportDir: supportDir))

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

    private func writeFixtureSnapshot(supportDir: URL, projectPath: URL) throws {
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

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
                    "collapsed": true,
                    "sessions": [
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
                    ],
                ],
            ],
            "sidebarOpen": true,
        ]

        let data = try JSONSerialization.data(withJSONObject: snapshot,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: supportDir.appendingPathComponent("session.json"), options: .atomic)
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
        _ = try productURL(named: "SacredTerminal")

        didBuildProducts = true
    }

    private static func sacredExecutableURL() throws -> URL {
        try productURL(named: "sacred")
    }

    private static func appExecutableURL() throws -> URL {
        try productURL(named: "SacredTerminal")
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
