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
import SacredTerminalSupport

/// Newline-delimited JSON control server over an AF_UNIX SOCK_STREAM socket.
final class SocketServer {

    // MARK: - Socket path

    /// The on-disk path of the control socket. The CLI reads this to find us.
    /// Lives under Application Support so it survives between launches and is
    /// per-user. AF_UNIX paths are limited (~104 bytes) so we keep it short.
    static func socketPath() -> String {
        SacredTerminalRuntime.controlSocketURL.path
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
        case appSupportDirectory(path: String, underlying: Error)

        var description: String {
            switch self {
            case .create(let e):       return "socket() failed: \(String(cString: strerror(e)))"
            case .bind(let e, let p):  return "bind(\(p)) failed: \(String(cString: strerror(e)))"
            case .listen(let e):       return "listen() failed: \(String(cString: strerror(e)))"
            case .pathTooLong(let p):  return "socket path too long for sockaddr_un: \(p)"
            case .appSupportDirectory(let p, let error):
                return "could not create app support directory \(p): \(error)"
            }
        }
    }

    /// Bind, listen, and start accepting connections on a background queue.
    func start() throws {
        do {
            try SacredTerminalRuntime.ensureAppSupportDirectory()
        } catch {
            throw SocketError.appSupportDirectory(path: SacredTerminalRuntime.appSupportDirectory.path,
                                                  underlying: error)
        }

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
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)

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
            let flags = fcntl(clientFD, F_GETFL, 0)
            if flags >= 0 {
                _ = fcntl(clientFD, F_SETFL, flags & ~O_NONBLOCK)
            }
            var noSigPipe: Int32 = 1
            _ = setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE,
                           &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            queue.async { [weak self] in self?.serve(clientFD) }
        }
    }

    // MARK: - Per-connection loop

    /// Read one command on the socket queue, then handle + reply on the main thread.
    private func serve(_ fd: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)

        readLoop: while true {
            let n = read(fd, &chunk, chunkSize)
            if n == 0 { close(fd); return }
            if n < 0 {
                if errno == EINTR { continue }
                close(fd); return
            }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.contains(0x0A) { break readLoop }
        }

        guard let nl = buffer.firstIndex(of: 0x0A) else { close(fd); return }
        let lineData = buffer.subdata(in: buffer.startIndex..<nl)
        let trimmed = trimCR(lineData)
        guard !trimmed.isEmpty else { close(fd); return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { close(fd); return }
            let reply = self.handle(line: trimmed)
            _ = self.writeLine(fd, reply)
            close(fd)
        }
    }

    private let chunkSize = 4096

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

        if E2EUIDriver.canHandle(cmd) {
            return E2EUIDriver.handle(command: cmd, object: obj)
        }

        switch cmd {
        case "status":
            return ["ok": true]

        case "get-state":
            return ["ok": true, "state": stateObject()]

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
            let worktree = obj["worktree"] as? Bool ?? false
            return newSession(projectID: projectID, agent: agent, worktree: worktree)

        case "add-project":
            return addProject(obj)

        case "toggle-sidebar":
            AppState.shared.toggleSidebar()
            return ["ok": true, "sidebarOpen": AppState.shared.sidebarOpen]

        case "set-sidebar":
            guard let open = obj["open"] as? Bool else {
                return ["ok": false, "error": "set-sidebar requires boolean \"open\""]
            }
            AppState.shared.setSidebarOpen(open)
            return ["ok": true, "sidebarOpen": AppState.shared.sidebarOpen]

        case "toggle-project":
            guard let id = obj["id"] as? String, !id.isEmpty else {
                return ["ok": false, "error": "toggle-project requires \"id\""]
            }
            return toggleProject(id: id)

        case "close-session":
            guard let id = obj["id"] as? String, !id.isEmpty else {
                return ["ok": false, "error": "close-session requires \"id\""]
            }
            return closeSession(id: id)

        case "send":
            guard let id = obj["id"] as? String, !id.isEmpty else {
                return ["ok": false, "error": "send requires \"id\""]
            }
            guard let message = obj["message"] as? String else {
                return ["ok": false, "error": "send requires \"message\""]
            }
            return sendMessage(id: id, message: message)

        case "set-status":
            guard let id = obj["id"] as? String, !id.isEmpty else {
                return ["ok": false, "error": "set-status requires \"id\""]
            }
            guard let raw = obj["status"] as? String, let status = Status(rawValue: raw) else {
                return ["ok": false, "error": "set-status requires status working|waiting|idle|done"]
            }
            return setStatus(id: id, status: status)

        case "add-pane":
            guard let id = obj["id"] as? String, !id.isEmpty else {
                return ["ok": false, "error": "add-pane requires \"id\""]
            }
            let rawKind = (obj["kind"] as? String) ?? Pane.Kind.shell.rawValue
            guard let kind = Pane.Kind(rawValue: rawKind) else {
                return ["ok": false, "error": "unknown pane kind \"\(rawKind)\""]
            }
            return addPane(sessionID: id, kind: kind)

        case "split-pane":
            guard let id = (obj["id"] as? String) ?? AppState.shared.activeSessionID, !id.isEmpty else {
                return ["ok": false, "error": "split-pane requires \"id\" or an active session"]
            }
            guard let direction = splitLayout(from: obj["direction"] as? String) else {
                return ["ok": false, "error": "split-pane requires direction right|down|horizontal|vertical"]
            }
            return splitPane(sessionID: id, direction: direction)

        case "focus-pane":
            guard let id = obj["id"] as? String, !id.isEmpty else {
                return ["ok": false, "error": "focus-pane requires \"id\""]
            }
            guard let paneID = obj["pane"] as? String, !paneID.isEmpty else {
                return ["ok": false, "error": "focus-pane requires \"pane\""]
            }
            return focusPane(sessionID: id, paneID: paneID)

        case "close-pane":
            guard let id = obj["id"] as? String, !id.isEmpty else {
                return ["ok": false, "error": "close-pane requires \"id\""]
            }
            guard let paneID = obj["pane"] as? String, !paneID.isEmpty else {
                return ["ok": false, "error": "close-pane requires \"pane\""]
            }
            return closePane(sessionID: id, paneID: paneID)

        case "toggle-browser":
            guard let id = (obj["id"] as? String) ?? AppState.shared.activeSessionID, !id.isEmpty else {
                return ["ok": false, "error": "toggle-browser requires \"id\" or an active session"]
            }
            return toggleBrowser(sessionID: id, force: obj["open"] as? Bool)

        case "set-browser-url":
            guard let id = obj["id"] as? String, !id.isEmpty else {
                return ["ok": false, "error": "set-browser-url requires \"id\""]
            }
            guard let url = obj["url"] as? String, !url.isEmpty else {
                return ["ok": false, "error": "set-browser-url requires \"url\""]
            }
            return setBrowserURL(sessionID: id, url: url)

        default:
            return ["ok": false, "error": "unknown cmd \"\(cmd)\""]
        }
    }

    // MARK: - Command implementations (all AppState access on the main thread)

    private func listSessions() -> [[String: Any]] {
        AppState.shared.allSessions.map { ctx in
            [
                "id": ctx.session.id,
                "projectID": ctx.project.id,
                "project": ctx.project.name,
                "agent": ctx.session.agent.rawValue,
                "task": ctx.session.task,
                "status": ctx.session.status.rawValue,
            ]
        }
    }

    private func focusSession(id: String) -> [String: Any] {
        guard AppState.shared.session(id) != nil else {
            return ["ok": false, "error": "no session \"\(id)\""]
        }
        AppState.shared.setActive(id)
        NotificationCenter.default.post(name: .sacredFocusSession, object: id)
        return ["ok": true, "id": id]
    }

    private func newSession(projectID: String, agent: AgentKey, worktree: Bool) -> [String: Any] {
        guard AppState.shared.projects.contains(where: { $0.id == projectID }) else {
            return ["ok": false, "error": "no project \"\(projectID)\""]
        }
        guard let session = AppState.shared.createSession(projectID: projectID,
                                                          agent: agent,
                                                          worktree: worktree) else {
            return ["ok": false, "error": "could not create session"]
        }
        return ["ok": true, "id": session.id, "session": sessionObject(session)]
    }

    private func addProject(_ obj: [String: Any]) -> [String: Any] {
        guard let path = (obj["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return ["ok": false, "error": "add-project requires \"path\""]
        }
        let name = obj["name"] as? String ?? ""
        let project = AppState.shared.addProject(name: name, path: path)
        return ["ok": true, "id": project.id, "project": projectObject(project)]
    }

    private func toggleProject(id: String) -> [String: Any] {
        guard let project = AppState.shared.projects.first(where: { $0.id == id }) else {
            return ["ok": false, "error": "no project \"\(id)\""]
        }
        AppState.shared.toggleCollapse(id)
        return ["ok": true, "id": id, "collapsed": project.collapsed]
    }

    private func closeSession(id: String) -> [String: Any] {
        guard AppState.shared.session(id) != nil else {
            return ["ok": false, "error": "no session \"\(id)\""]
        }
        AppState.shared.closeSession(id)
        return ["ok": true, "id": id, "activeSessionID": AppState.shared.activeSessionID ?? NSNull()]
    }

    private func sendMessage(id: String, message: String) -> [String: Any] {
        guard AppState.shared.session(id) != nil else {
            return ["ok": false, "error": "no session \"\(id)\""]
        }
        AppState.shared.send(to: id, message: message)
        guard let session = AppState.shared.session(id)?.session else {
            return ["ok": false, "error": "no session \"\(id)\""]
        }
        return ["ok": true, "id": id, "session": sessionObject(session)]
    }

    private func setStatus(id: String, status: Status) -> [String: Any] {
        guard AppState.shared.session(id) != nil else {
            return ["ok": false, "error": "no session \"\(id)\""]
        }
        AppState.shared.setStatus(id, status)
        return ["ok": true, "id": id, "status": status.rawValue]
    }

    private func addPane(sessionID: String, kind: Pane.Kind) -> [String: Any] {
        guard AppState.shared.session(sessionID) != nil else {
            return ["ok": false, "error": "no session \"\(sessionID)\""]
        }
        guard let pane = AppState.shared.addPane(sessionID, kind: kind) else {
            return ["ok": false, "error": "could not add pane"]
        }
        return ["ok": true, "id": pane.id, "pane": paneObject(pane)]
    }

    private func splitPane(sessionID: String, direction: SplitLayout) -> [String: Any] {
        guard AppState.shared.session(sessionID) != nil else {
            return ["ok": false, "error": "no session \"\(sessionID)\""]
        }
        AppState.shared.split(sessionID, direction)
        guard let session = AppState.shared.session(sessionID)?.session else {
            return ["ok": false, "error": "no session \"\(sessionID)\""]
        }
        return ["ok": true, "id": sessionID, "session": sessionObject(session)]
    }

    private func focusPane(sessionID: String, paneID: String) -> [String: Any] {
        guard let session = AppState.shared.session(sessionID)?.session else {
            return ["ok": false, "error": "no session \"\(sessionID)\""]
        }
        guard session.panes.contains(where: { $0.id == paneID }) else {
            return ["ok": false, "error": "no pane \"\(paneID)\""]
        }
        AppState.shared.setActivePane(sessionID, paneID)
        return ["ok": true, "id": sessionID, "activePaneID": paneID]
    }

    private func closePane(sessionID: String, paneID: String) -> [String: Any] {
        guard let session = AppState.shared.session(sessionID)?.session else {
            return ["ok": false, "error": "no session \"\(sessionID)\""]
        }
        guard session.panes.contains(where: { $0.id == paneID }) else {
            return ["ok": false, "error": "no pane \"\(paneID)\""]
        }
        guard session.panes.count > 1 else {
            return ["ok": false, "error": "cannot close the only pane in session \"\(sessionID)\""]
        }
        AppState.shared.closePane(sessionID, paneID)
        guard let updated = AppState.shared.session(sessionID)?.session else {
            return ["ok": false, "error": "no session \"\(sessionID)\""]
        }
        return ["ok": true, "id": sessionID, "session": sessionObject(updated)]
    }

    private func toggleBrowser(sessionID: String, force: Bool?) -> [String: Any] {
        guard AppState.shared.session(sessionID) != nil else {
            return ["ok": false, "error": "no session \"\(sessionID)\""]
        }
        AppState.shared.toggleBrowser(sessionID, force: force)
        guard let session = AppState.shared.session(sessionID)?.session else {
            return ["ok": false, "error": "no session \"\(sessionID)\""]
        }
        return ["ok": true, "id": sessionID, "browserOpen": session.browserOpen]
    }

    private func setBrowserURL(sessionID: String, url: String) -> [String: Any] {
        guard AppState.shared.session(sessionID) != nil else {
            return ["ok": false, "error": "no session \"\(sessionID)\""]
        }
        AppState.shared.setBrowserURL(sessionID, url)
        return ["ok": true, "id": sessionID, "browserURL": url]
    }

    private func splitLayout(from raw: String?) -> SplitLayout? {
        switch raw?.lowercased() {
        case "right", "horizontal": return .horizontal
        case "down", "vertical": return .vertical
        default: return nil
        }
    }

    private func stateObject() -> [String: Any] {
        let state = AppState.shared
        return [
            "activeSessionID": state.activeSessionID ?? NSNull(),
            "sidebarOpen": state.sidebarOpen,
            "agents": Agents.order.map(agentObject),
            "projects": state.projects.map(projectObject),
        ]
    }

    private func agentObject(_ key: AgentKey) -> [String: Any] {
        let def = Agents.def(key)
        return [
            "key": key.rawValue,
            "name": def.name,
            "provider": def.provider,
            "enabled": AppState.shared.agentEnabled.contains(key),
            "pinned": AppState.shared.pinnedAgents.contains(key),
        ]
    }

    private func projectObject(_ project: Project) -> [String: Any] {
        [
            "id": project.id,
            "name": project.name,
            "path": project.path,
            "collapsed": project.collapsed,
            "sessions": project.sessions.map(sessionObject),
        ]
    }

    private func sessionObject(_ session: Session) -> [String: Any] {
        [
            "id": session.id,
            "agent": session.agent.rawValue,
            "task": session.task,
            "status": session.status.rawValue,
            "worktree": session.worktree,
            "yolo": session.yolo,
            "browserOpen": session.browserOpen,
            "browserURL": session.browserURL,
            "activePaneID": session.activePaneID,
            "splitLayout": session.splitLayout.rawValue,
            "panes": session.panes.map(paneObject),
        ]
    }

    private func paneObject(_ pane: Pane) -> [String: Any] {
        [
            "id": pane.id,
            "title": pane.title,
            "kind": pane.kind.rawValue,
            "started": pane.started,
        ]
    }

    // MARK: - Helpers

    /// Serialize a reply, falling back to a minimal error object if encoding fails.
    private func jsonData(_ object: [String: Any]) -> Data {
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: []) {
            return data
        }
        return Data(#"{"ok":false,"error":"encode failed"}"#.utf8)
    }
}
