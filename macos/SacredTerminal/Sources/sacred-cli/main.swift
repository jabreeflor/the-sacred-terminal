//  main.swift  (sacred-cli)
//  The `sacred` CLI — a tiny client that drives a running instance of The Sacred
//  Terminal over its Unix-domain control socket. It speaks the exact same
//  newline-delimited JSON protocol as `Socket/SocketServer.swift` in the app:
//  one JSON command per line in, one JSON reply per line out.
//
//  This target is independent of the app's Swift types (it can't import them), so
//  everything here is pure Foundation + Darwin: we open an AF_UNIX SOCK_STREAM
//  socket by hand, write the command, read one reply line, and print results.
//
//  Commands (mirroring SocketServer.handle):
//    sacred ls                       -> {"cmd":"list-sessions"}
//    sacred focus <id>               -> {"cmd":"focus","id":<id>}
//    sacred new   <projectId> <key>  -> {"cmd":"new-session","project":<id>,"agent":<key>}
//    sacred status                   -> {"cmd":"status"}

import Foundation
import Darwin
import SacredTerminalSupport

// MARK: - Socket path

/// The on-disk path of the app's control socket. Must match
/// `SocketServer.socketPath()`: <Application Support>/SacredTerminal/control.sock.
func controlSocketPath() -> String {
    SacredTerminalRuntime.controlSocketURL.path
}

// MARK: - Errors

enum CLIError: Error, CustomStringConvertible {
    case connect(path: String, errno: Int32)
    case notRunning(path: String)
    case write(errno: Int32)
    case eof
    case badReply(String)
    case server(String)

    var description: String {
        switch self {
        case .connect(let p, let e):
            return "could not connect to \(p): \(String(cString: strerror(e)))"
        case .notRunning(let p):
            return "The Sacred Terminal does not appear to be running (no socket at \(p)). Launch the app first."
        case .write(let e):
            return "write failed: \(String(cString: strerror(e)))"
        case .eof:
            return "connection closed before a reply was received"
        case .badReply(let s):
            return "unexpected reply from app: \(s)"
        case .server(let s):
            return s
        }
    }
}

// MARK: - Connection

/// A minimal blocking AF_UNIX client: connect, send one command line, read one
/// newline-delimited JSON reply.
final class ControlConnection {
    private let fd: Int32
    private let path: String

    init(path: String) throws {
        self.path = path

        // If the socket file isn't there, the app almost certainly isn't running.
        if !FileManager.default.fileExists(atPath: path) {
            throw CLIError.notRunning(path: path)
        }

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { throw CLIError.connect(path: path, errno: errno) }

        // Build sockaddr_un, guarding against overflowing sun_path (~104 bytes).
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < capacity else {
            close(sock)
            throw CLIError.connect(path: path, errno: ENAMETOOLONG)
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                for (i, b) in pathBytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[pathBytes.count] = 0
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(sock, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let e = errno
            close(sock)
            // A stale socket file (app crashed) refuses the connection.
            if e == ECONNREFUSED || e == ENOENT || e == ENOTSOCK {
                throw CLIError.notRunning(path: path)
            }
            throw CLIError.connect(path: path, errno: e)
        }

        self.fd = sock
    }

    deinit { close(fd) }

    /// Send one command object as a JSON line, then read exactly one reply line.
    func request(_ command: [String: Any]) throws -> [String: Any] {
        try writeLine(command)
        let line = try readLine()
        guard let obj = (try? JSONSerialization.jsonObject(with: line, options: [])) as? [String: Any] else {
            throw CLIError.badReply(String(decoding: line, as: UTF8.self))
        }
        return obj
    }

    private func writeLine(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            throw CLIError.badReply("could not encode command")
        }
        data.append(0x0A)  // newline-delimited protocol
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            let total = raw.count
            while offset < total {
                let n = write(fd, base + offset, total - offset)
                if n <= 0 {
                    if n < 0 && errno == EINTR { continue }
                    throw CLIError.write(errno: errno)
                }
                offset += n
            }
        }
    }

    /// Read bytes until the first newline; return the line without the newline.
    private func readLine() throws -> Data {
        var buffer = Data()
        let chunkSize = 4096
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let n = read(fd, &chunk, chunkSize)
            if n == 0 {
                // EOF with a complete unterminated line is still usable.
                if !buffer.isEmpty { return trimCR(buffer) }
                throw CLIError.eof
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw CLIError.write(errno: errno)
            }
            buffer.append(contentsOf: chunk[0..<n])
            if let nl = buffer.firstIndex(of: 0x0A) {
                return trimCR(buffer.subdata(in: buffer.startIndex..<nl))
            }
        }
    }

    private func trimCR(_ data: Data) -> Data {
        guard let last = data.last, last == 0x0D else { return data }
        return data.subdata(in: data.startIndex..<data.index(before: data.endIndex))
    }
}

// MARK: - Output helpers

func printErr(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

/// Pull a human error out of a reply, defaulting to a generic message.
func serverError(_ reply: [String: Any]) -> CLIError {
    let msg = (reply["error"] as? String) ?? "command failed"
    return CLIError.server(msg)
}

let usage = """
sacred — control The Sacred Terminal from the command line

USAGE:
  sacred ls                       List all sessions (id, project, agent, task, status)
  sacred focus <id>               Focus the session with the given id
  sacred new <projectId> <agent>  Create a session in a project with the given agent
  sacred status                   Check whether the app is running

AGENTS:
  claude  codex  cursor  gemini  copilot  opencode  shell
"""

/// Pad a string to a fixed width (for the `ls` table). Truncates overlong cells.
func pad(_ s: String, _ width: Int) -> String {
    if s.count == width { return s }
    if s.count < width { return s + String(repeating: " ", count: width - s.count) }
    if width <= 1 { return String(s.prefix(width)) }
    return String(s.prefix(width - 1)) + "…"
}

// MARK: - Commands

func runList() throws {
    let conn = try ControlConnection(path: controlSocketPath())
    let reply = try conn.request(["cmd": "list-sessions"])
    guard (reply["ok"] as? Bool) == true else { throw serverError(reply) }

    let sessions = (reply["sessions"] as? [[String: Any]]) ?? []
    if sessions.isEmpty {
        print("No sessions.")
        return
    }

    func cell(_ row: [String: Any], _ key: String) -> String {
        (row[key] as? String) ?? ""
    }

    // Column widths sized to content, with sensible caps so the table stays tidy.
    let idW      = max(2,  sessions.map { cell($0, "id").count }.max() ?? 2)
    let projW    = min(20, max(7,  sessions.map { cell($0, "project").count }.max() ?? 7))
    let agentW   = min(10, max(5,  sessions.map { cell($0, "agent").count }.max() ?? 5))
    let statusW  = min(8,  max(6,  sessions.map { cell($0, "status").count }.max() ?? 6))
    let taskW    = min(48, max(4,  sessions.map { cell($0, "task").count }.max() ?? 4))

    let header = [pad("ID", idW), pad("PROJECT", projW), pad("AGENT", agentW),
                  pad("STATUS", statusW), pad("TASK", taskW)].joined(separator: "  ")
    print(header)
    print(String(repeating: "-", count: header.count))

    for row in sessions {
        let line = [
            pad(cell(row, "id"), idW),
            pad(cell(row, "project"), projW),
            pad(cell(row, "agent"), agentW),
            pad(cell(row, "status"), statusW),
            pad(cell(row, "task"), taskW),
        ].joined(separator: "  ")
        print(line)
    }
}

func runFocus(id: String) throws {
    let conn = try ControlConnection(path: controlSocketPath())
    let reply = try conn.request(["cmd": "focus", "id": id])
    guard (reply["ok"] as? Bool) == true else { throw serverError(reply) }
    print("Focused session \((reply["id"] as? String) ?? id).")
}

func runNew(projectID: String, agent: String) throws {
    let conn = try ControlConnection(path: controlSocketPath())
    // NOTE: SocketServer expects the JSON field "project" (not "projectId").
    let reply = try conn.request(["cmd": "new-session", "project": projectID, "agent": agent])
    guard (reply["ok"] as? Bool) == true else { throw serverError(reply) }
    print("Created session \((reply["id"] as? String) ?? "?") in project \(projectID) (\(agent)).")
}

func runStatus() throws {
    do {
        let conn = try ControlConnection(path: controlSocketPath())
        let reply = try conn.request(["cmd": "status"])
        if (reply["ok"] as? Bool) == true {
            print("The Sacred Terminal is running.")
        } else {
            throw serverError(reply)
        }
    } catch CLIError.notRunning {
        // `status` reports a clean "not running" rather than erroring out.
        print("The Sacred Terminal is not running.")
        exit(1)
    }
}

// MARK: - Entry point

func main() {
    signal(SIGPIPE, SIG_IGN)

    var args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else {
        print(usage)
        exit(2)
    }
    args.removeFirst()

    do {
        switch command {
        case "ls", "list", "list-sessions":
            try runList()

        case "focus":
            guard let id = args.first, !id.isEmpty else {
                printErr("usage: sacred focus <id>")
                exit(2)
            }
            try runFocus(id: id)

        case "new", "new-session":
            guard args.count >= 2, !args[0].isEmpty, !args[1].isEmpty else {
                printErr("usage: sacred new <projectId> <agentKey>")
                exit(2)
            }
            try runNew(projectID: args[0], agent: args[1])

        case "status":
            try runStatus()

        case "-h", "--help", "help":
            print(usage)

        default:
            printErr("sacred: unknown command \"\(command)\"\n")
            printErr(usage)
            exit(2)
        }
    } catch let error as CLIError {
        printErr("sacred: \(error)")
        exit(1)
    } catch {
        printErr("sacred: \(error)")
        exit(1)
    }
}

main()
