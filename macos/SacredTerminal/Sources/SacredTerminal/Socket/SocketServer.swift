//  SocketServer.swift
//  A Unix-domain-socket control API for The Sacred Terminal (spec §6 — "one
//  programmable surface"). Modeled on cmux's TerminalController: a long-lived
//  AF_UNIX SOCK_STREAM socket that a small CLI (or any client) connects to and
//  drives over newline-delimited JSON. Each line in is one command; each line
//  out is one JSON reply.
//
//  Pure Foundation + Darwin sockets — no third-party deps. AppState is the single
//  source of truth and is only ever touched on the main thread, so every command
//  that reads or mutates it hops onto DispatchQueue.main (sync for reads so we can
//  build the reply, async for fire-and-forget mutations/posts).

import Foundation
import Darwin

/// Newline-delimited JSON control server over an AF_UNIX SOCK_STREAM socket.
final class SocketServer {

    // MARK: - Socket path

    /// The on-disk path of the control socket. The CLI reads this to find us.
    /// Lives under Application Support so it survives between launches and is
    /// per-user. AF_UNIX paths are limited (~104 bytes) so we keep it short.
    static func socketPath() -> String {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("SacredTerminal", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("control.sock").path
    }

    // MARK: - State

    private let path: String
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.sacredterminal.socket", qos: .utility)

    init() {
        self.path = SocketServer.socketPath()
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    enum SocketError: Error, CustomStringConvertible {
        case create(errno: Int32)
        case bind(errno: Int32, path: String)
        case listen(errno: Int32)
        case pathTooLong(path: String)

        var description: String {
            switch self {
            case .create(let e):       return "socket() failed: \(String(cString: strerror(e)))"
            case .bind(let e, let p):  return "bind(\(p)) failed: \(String(cString: strerror(e)))"
            case .listen(let e):       return "listen() failed: \(String(cString: strerror(e)))"
            case .pathTooLong(let p):  return "socket path too long for sockaddr_un: \(p)"
            }
        }
    }

    /// Bind, listen, and start accepting connections on a background queue.
    func start() throws {
        // A fresh socket can't bind to an existing path — remove a stale one.
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.create(errno: errno) }

        // Build the sockaddr_un, guarding against overflowing sun_path.
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)   // typically 104
        guard pathBytes.count < capacity else {
            close(fd)
            throw SocketError.pathTooLong(path: path)
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                for (i, b) in pathBytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[pathBytes.count] = 0
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let e = errno
            close(fd)
            throw SocketError.bind(errno: e, path: path)
        }

        // Restrict the socket to the owning user (control == drive the app).
        chmod(path, 0o600)

        guard listen(fd, 16) == 0 else {
            let e = errno
            close(fd)
            unlink(path)
            throw SocketError.listen(errno: e)
        }

        listenFD = fd

        // Accept loop driven by a DispatchSource so we never block a thread.
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        acceptSource = source
        source.resume()
    }

    /// Tear down the listener and remove the socket file.
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 { listenFD = -1 }   // closed by the cancel handler
        unlink(path)
    }

    // MARK: - Accept

    private func acceptPending() {
        // Drain everything currently pending so we don't starve the source.
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                // EWOULDBLOCK/EAGAIN: nothing more to accept right now.
                if errno == EWOULDBLOCK || errno == EAGAIN { return }
                if errno == EINTR { continue }
                return
            }
            queue.async { [weak self] in self?.serve(clientFD) }
        }
    }

    // MARK: - Per-connection loop

    /// Read newline-delimited JSON commands until EOF, replying to each.
    private func serve(_ fd: Int32) {
        defer { close(fd) }

        var buffer = Data()
        let chunkSize = 4096
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        while true {
            let n = read(fd, &chunk, chunkSize)
            if n == 0 { break }                    // peer closed
            if n < 0 {
                if errno == EINTR { continue }
                break
            }
            buffer.append(contentsOf: chunk[0..<n])

            // Process every complete line we have so far.
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                // Advance past the newline.
                buffer.removeSubrange(buffer.startIndex...nl)
                let trimmed = trimCR(lineData)
                if trimmed.isEmpty { continue }
                let reply = handle(line: trimmed)
                if !writeLine(fd, reply) { return }
            }
        }
    }

    /// Strip a trailing CR so CRLF clients are handled gracefully.
    private func trimCR(_ data: Data) -> Data {
        guard let last = data.last, last == 0x0D else { return data }
        return data.subdata(in: data.startIndex..<data.index(before: data.endIndex))
    }

    /// Write one JSON object followed by a newline. Returns false on a hard error.
    @discardableResult
    private func writeLine(_ fd: Int32, _ object: [String: Any]) -> Bool {
        var data = jsonData(object)
        data.append(0x0A)
        return writeAll(fd, data)
    }

    private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            let total = raw.count
            while offset < total {
                let n = write(fd, base + offset, total - offset)
                if n <= 0 {
                    if n < 0 && errno == EINTR { continue }
                    return false
                }
                offset += n
            }
            return true
        }
    }

    // MARK: - Command dispatch

    /// Decode one JSON line and produce the reply object. Robust to garbage:
    /// any decode/shape problem becomes a structured error reply, never a crash.
    private func handle(line: Data) -> [String: Any] {
        let parsed = try? JSONSerialization.jsonObject(with: line, options: [])
        guard let obj = parsed as? [String: Any] else {
            return ["ok": false, "error": "invalid JSON"]
        }
        guard let cmd = (obj["cmd"] as? String)?.trimmingCharacters(in: .whitespaces),
              !cmd.isEmpty else {
            return ["ok": false, "error": "missing \"cmd\""]
        }

        switch cmd {
        case "status":
            return ["ok": true]

        case "list-sessions":
            return ["ok": true, "sessions": listSessions()]

        case "focus":
            guard let id = obj["id"] as? String, !id.isEmpty else {
                return ["ok": false, "error": "focus requires \"id\""]
            }
            return focusSession(id: id)

        case "new-session":
            guard let projectID = obj["project"] as? String, !projectID.isEmpty else {
                return ["ok": false, "error": "new-session requires \"project\""]
            }
            let agentRaw = (obj["agent"] as? String) ?? AgentKey.shell.rawValue
            guard let agent = AgentKey(rawValue: agentRaw) else {
                return ["ok": false, "error": "unknown agent \"\(agentRaw)\""]
            }
            return newSession(projectID: projectID, agent: agent)

        default:
            return ["ok": false, "error": "unknown cmd \"\(cmd)\""]
        }
    }

    // MARK: - Command implementations (all AppState access on the main thread)

    private func listSessions() -> [[String: Any]] {
        return mainSync {
            AppState.shared.allSessions.map { ctx in
                [
                    "id": ctx.session.id,
                    "project": ctx.project.name,
                    "agent": ctx.session.agent.rawValue,
                    "task": ctx.session.task,
                    "status": ctx.session.status.rawValue,
                ]
            }
        }
    }

    private func focusSession(id: String) -> [String: Any] {
        // Validate the id against state, then ask the main window to snap to it.
        let exists = mainSync { AppState.shared.session(id) != nil }
        guard exists else {
            return ["ok": false, "error": "no session \"\(id)\""]
        }
        DispatchQueue.main.async {
            AppState.shared.setActive(id)
            NotificationCenter.default.post(name: .sacredFocusSession, object: id)
        }
        return ["ok": true, "id": id]
    }

    private func newSession(projectID: String, agent: AgentKey) -> [String: Any] {
        // Resolve the project on the main thread, create the session there, and
        // hand back the new id so the caller can immediately drive it.
        let result: [String: Any] = mainSync {
            guard AppState.shared.projects.contains(where: { $0.id == projectID }) else {
                return ["ok": false, "error": "no project \"\(projectID)\""]
            }
            guard let session = AppState.shared.createSession(projectID: projectID,
                                                              agent: agent,
                                                              worktree: false) else {
                return ["ok": false, "error": "could not create session"]
            }
            return ["ok": true, "id": session.id]
        }
        return result
    }

    // MARK: - Helpers

    /// Run a block on the main thread and return its value, even when called from
    /// the socket queue. If we're already on main (shouldn't happen), run inline
    /// to avoid a deadlock.
    private func mainSync<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }

    /// Serialize a reply, falling back to a minimal error object if encoding fails.
    private func jsonData(_ object: [String: Any]) -> Data {
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: []) {
            return data
        }
        return Data(#"{"ok":false,"error":"encode failed"}"#.utf8)
    }
}
