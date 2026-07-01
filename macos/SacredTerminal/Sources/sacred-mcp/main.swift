import Darwin
import Foundation
import SacredTerminalSupport

private let protocolVersion = "2025-03-26"
private let supportedProtocolVersions = Set(["2025-03-26", "2024-11-05"])

private enum Framing {
    case newline
    case contentLength
}

private struct RPCError: Error {
    let code: Int
    let message: String
    let data: Any?

    init(_ code: Int, _ message: String, data: Any? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

private struct MCPTool {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    var definition: [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": inputSchema,
        ]
    }
}

private final class SacredMCPServer {
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput
    private var buffer = Data()

    func run() {
        signal(SIGPIPE, SIG_IGN)

        while true {
            let chunk = input.availableData
            if chunk.isEmpty {
                drainFinalLine()
                break
            }
            buffer.append(chunk)
            drainFrames()
        }
    }

    private func drainFrames() {
        while let frame = nextFrame() {
            handleFrame(data: frame.data, framing: frame.framing)
        }
    }

    private func drainFinalLine() {
        guard !buffer.isEmpty, !startsWithContentLengthHeader() else { return }
        var data = buffer
        buffer.removeAll()
        if data.last == 0x0D {
            data = data.dropLast()
        }
        handleFrame(data: data, framing: .newline)
    }

    private func nextFrame() -> (data: Data, framing: Framing)? {
        guard !buffer.isEmpty else { return nil }

        if startsWithContentLengthHeader() {
            let separator = Data("\r\n\r\n".utf8)
            guard let headerRange = buffer.range(of: separator),
                  let headerText = String(data: buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound),
                                          encoding: .utf8),
                  let length = contentLength(from: headerText) else {
                return nil
            }

            let bodyStart = headerRange.upperBound
            let bodyEnd = bodyStart + length
            guard buffer.count >= bodyEnd else { return nil }

            let body = buffer.subdata(in: bodyStart..<bodyEnd)
            buffer.removeSubrange(buffer.startIndex..<bodyEnd)
            return (body, .contentLength)
        }

        guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
        var line = buffer.subdata(in: buffer.startIndex..<newline)
        buffer.removeSubrange(buffer.startIndex...newline)
        if line.last == 0x0D {
            line = line.dropLast()
        }
        return (line, .newline)
    }

    private func startsWithContentLengthHeader() -> Bool {
        let prefix = buffer.prefix(min(buffer.count, 14))
        return String(data: prefix, encoding: .utf8)?.lowercased().hasPrefix("content-length") == true
    }

    private func contentLength(from headerText: String) -> Int? {
        headerText
            .components(separatedBy: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                return Int(parts[1])
            }
            .first
    }

    private func handleFrame(data: Data, framing: Framing) {
        guard !data.isEmpty else { return }
        do {
            let message = try JSONSerialization.jsonObject(with: data)
            if let response = handleMessage(message) {
                send(response, framing: framing)
            }
        } catch {
            send(errorResponse(id: NSNull(), error: RPCError(-32700, "Parse error")), framing: framing)
        }
    }

    private func handleMessage(_ message: Any) -> Any? {
        if let batch = message as? [Any] {
            let responses = batch.compactMap(handleMessage)
            return responses.isEmpty ? nil : responses
        }

        guard let object = message as? [String: Any] else {
            return errorResponse(id: NSNull(), error: RPCError(-32600, "Invalid request"))
        }

        let hasID = object.keys.contains("id")
        let id = object["id"] ?? NSNull()
        guard let method = object["method"] as? String else {
            return hasID ? errorResponse(id: id, error: RPCError(-32600, "Invalid request")) : nil
        }

        guard hasID else {
            return nil
        }

        do {
            let result = try handleRequest(method: method, params: object["params"])
            return response(id: id, result: result)
        } catch let error as RPCError {
            return errorResponse(id: id, error: error)
        } catch {
            return errorResponse(id: id, error: RPCError(-32603, String(describing: error)))
        }
    }

    private func handleRequest(method: String, params: Any?) throws -> Any {
        switch method {
        case "initialize":
            return initialize(params: params)
        case "ping":
            return [:]
        case "tools/list":
            return ["tools": tools.map(\.definition)]
        case "tools/call":
            return try callTool(params: params)
        case "shutdown":
            return NSNull()
        default:
            throw RPCError(-32601, "Method not found: \(method)")
        }
    }

    private func initialize(params: Any?) -> [String: Any] {
        let requested = ((params as? [String: Any])?["protocolVersion"] as? String) ?? protocolVersion
        let selected = supportedProtocolVersions.contains(requested) ? requested : protocolVersion
        return [
            "protocolVersion": selected,
            "capabilities": [
                "tools": [
                    "listChanged": false,
                ],
            ],
            "serverInfo": [
                "name": "sacred-terminal-mcp",
                "version": "0.1.0",
            ],
            "instructions": "Use these tools to drive the same Sacred Terminal workspace state that the AppKit UI reads and mutates.",
        ]
    }

    private func callTool(params: Any?) throws -> [String: Any] {
        guard let params = params as? [String: Any],
              let name = params["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RPCError(-32602, "tools/call requires a tool name")
        }
        guard tools.contains(where: { $0.name == name }) else {
            throw RPCError(-32602, "Unknown tool: \(name)")
        }

        let arguments = (params["arguments"] as? [String: Any]) ?? [:]
        let command = try socketCommand(for: name, arguments: arguments)
        do {
            let reply = try SacredTerminalControlClient().request(command)
            let ok = reply["ok"] as? Bool == true
            return toolResult(reply: reply, isError: !ok)
        } catch {
            return toolResult(reply: ["ok": false, "error": String(describing: error)], isError: true)
        }
    }

    private func response(id: Any, result: Any) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "result": result,
        ]
    }

    private func errorResponse(id: Any, error: RPCError) -> [String: Any] {
        var body: [String: Any] = [
            "code": error.code,
            "message": error.message,
        ]
        if let data = error.data {
            body["data"] = data
        }
        return [
            "jsonrpc": "2.0",
            "id": id,
            "error": body,
        ]
    }

    private func send(_ object: Any, framing: Framing) {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object) else {
            return
        }

        switch framing {
        case .newline:
            data.append(0x0A)
            output.write(data)
        case .contentLength:
            var framed = Data("Content-Length: \(data.count)\r\n\r\n".utf8)
            framed.append(data)
            output.write(framed)
        }
    }
}

private let tools: [MCPTool] = [
    MCPTool(
        name: "sacred_get_state",
        description: "Read projects, sessions, panes, browser state, sidebar state, and available agents from the running app.",
        inputSchema: objectSchema()
    ),
    MCPTool(
        name: "sacred_list_sessions",
        description: "List sessions with their project, agent, task, and status.",
        inputSchema: objectSchema()
    ),
    MCPTool(
        name: "sacred_add_project",
        description: "Add a project folder to the rail, matching the Add Project UI action.",
        inputSchema: objectSchema(
            properties: [
                "path": stringSchema("Absolute folder path for the project."),
                "name": stringSchema("Optional display name. Defaults to the folder name."),
            ],
            required: ["path"]
        )
    ),
    MCPTool(
        name: "sacred_toggle_sidebar",
        description: "Toggle the side rail, or set it open/closed when the open argument is provided.",
        inputSchema: objectSchema(properties: [
            "open": boolSchema("Optional target state for the side rail."),
        ])
    ),
    MCPTool(
        name: "sacred_toggle_project",
        description: "Collapse or expand a project row.",
        inputSchema: objectSchema(
            properties: ["project_id": stringSchema("Project id.")],
            required: ["project_id"]
        )
    ),
    MCPTool(
        name: "sacred_create_session",
        description: "Create an agent-bound session under a project, matching the rail quick-pick or agent picker.",
        inputSchema: objectSchema(
            properties: [
                "project_id": stringSchema("Project id."),
                "agent": stringSchema("Agent key.", allowed: ["claude", "codex", "cursor", "gemini", "copilot", "opencode", "shell"]),
                "worktree": boolSchema("Whether the session should be marked as worktree-backed."),
            ],
            required: ["project_id", "agent"]
        )
    ),
    MCPTool(
        name: "sacred_focus_session",
        description: "Focus a session, matching a click on its rail row.",
        inputSchema: objectSchema(
            properties: ["session_id": stringSchema("Session id.")],
            required: ["session_id"]
        )
    ),
    MCPTool(
        name: "sacred_close_session",
        description: "Close a session, matching the rail close button.",
        inputSchema: objectSchema(
            properties: ["session_id": stringSchema("Session id.")],
            required: ["session_id"]
        )
    ),
    MCPTool(
        name: "sacred_send_to_session",
        description: "Send text to a session's app model, matching the send-to-agent interaction.",
        inputSchema: objectSchema(
            properties: [
                "session_id": stringSchema("Session id."),
                "message": stringSchema("Message text."),
            ],
            required: ["session_id", "message"]
        )
    ),
    MCPTool(
        name: "sacred_set_session_status",
        description: "Set a session status so the rail and menu-bar state reflect the new status.",
        inputSchema: objectSchema(
            properties: [
                "session_id": stringSchema("Session id."),
                "status": stringSchema("Status value.", allowed: ["working", "waiting", "idle", "done"]),
            ],
            required: ["session_id", "status"]
        )
    ),
    MCPTool(
        name: "sacred_add_pane",
        description: "Open a new terminal pane/tab in a session, matching the New Tab UI action.",
        inputSchema: objectSchema(
            properties: [
                "session_id": stringSchema("Session id."),
                "kind": stringSchema("Pane kind.", allowed: ["shell", "agent"]),
            ],
            required: ["session_id"]
        )
    ),
    MCPTool(
        name: "sacred_split_pane",
        description: "Split the active or given session right/down, matching the split buttons and shortcuts.",
        inputSchema: objectSchema(
            properties: [
                "session_id": stringSchema("Optional session id. Defaults to the active session."),
                "direction": stringSchema("Split direction.", allowed: ["right", "down", "horizontal", "vertical"]),
            ],
            required: ["direction"]
        )
    ),
    MCPTool(
        name: "sacred_focus_pane",
        description: "Focus a terminal pane/tab inside a session.",
        inputSchema: objectSchema(
            properties: [
                "session_id": stringSchema("Session id."),
                "pane_id": stringSchema("Pane id."),
            ],
            required: ["session_id", "pane_id"]
        )
    ),
    MCPTool(
        name: "sacred_close_pane",
        description: "Close a terminal pane/tab inside a session.",
        inputSchema: objectSchema(
            properties: [
                "session_id": stringSchema("Session id."),
                "pane_id": stringSchema("Pane id."),
            ],
            required: ["session_id", "pane_id"]
        )
    ),
    MCPTool(
        name: "sacred_toggle_browser",
        description: "Toggle or set the integrated browser for a session, matching the titlebar globe button.",
        inputSchema: objectSchema(properties: [
            "session_id": stringSchema("Optional session id. Defaults to the active session."),
            "open": boolSchema("Optional target open state."),
        ])
    ),
    MCPTool(
        name: "sacred_set_browser_url",
        description: "Set the integrated browser URL for a session.",
        inputSchema: objectSchema(
            properties: [
                "session_id": stringSchema("Session id."),
                "url": stringSchema("URL to load or store in the browser bar."),
            ],
            required: ["session_id", "url"]
        )
    ),
]

private func socketCommand(for toolName: String, arguments: [String: Any]) throws -> [String: Any] {
    switch toolName {
    case "sacred_get_state":
        return ["cmd": "get-state"]
    case "sacred_list_sessions":
        return ["cmd": "list-sessions"]
    case "sacred_add_project":
        var command: [String: Any] = ["cmd": "add-project", "path": try requiredString(arguments, "path")]
        if let name = optionalString(arguments, "name") { command["name"] = name }
        return command
    case "sacred_toggle_sidebar":
        if let open = arguments["open"] as? Bool {
            return ["cmd": "set-sidebar", "open": open]
        }
        return ["cmd": "toggle-sidebar"]
    case "sacred_toggle_project":
        return ["cmd": "toggle-project", "id": try requiredString(arguments, "project_id")]
    case "sacred_create_session":
        var command: [String: Any] = [
            "cmd": "new-session",
            "project": try requiredString(arguments, "project_id"),
            "agent": try requiredString(arguments, "agent"),
        ]
        if let worktree = arguments["worktree"] as? Bool { command["worktree"] = worktree }
        return command
    case "sacred_focus_session":
        return ["cmd": "focus", "id": try requiredString(arguments, "session_id")]
    case "sacred_close_session":
        return ["cmd": "close-session", "id": try requiredString(arguments, "session_id")]
    case "sacred_send_to_session":
        return [
            "cmd": "send",
            "id": try requiredString(arguments, "session_id"),
            "message": try requiredString(arguments, "message"),
        ]
    case "sacred_set_session_status":
        return [
            "cmd": "set-status",
            "id": try requiredString(arguments, "session_id"),
            "status": try requiredString(arguments, "status"),
        ]
    case "sacred_add_pane":
        var command: [String: Any] = ["cmd": "add-pane", "id": try requiredString(arguments, "session_id")]
        if let kind = optionalString(arguments, "kind") { command["kind"] = kind }
        return command
    case "sacred_split_pane":
        var command: [String: Any] = ["cmd": "split-pane", "direction": try requiredString(arguments, "direction")]
        if let sessionID = optionalString(arguments, "session_id") { command["id"] = sessionID }
        return command
    case "sacred_focus_pane":
        return [
            "cmd": "focus-pane",
            "id": try requiredString(arguments, "session_id"),
            "pane": try requiredString(arguments, "pane_id"),
        ]
    case "sacred_close_pane":
        return [
            "cmd": "close-pane",
            "id": try requiredString(arguments, "session_id"),
            "pane": try requiredString(arguments, "pane_id"),
        ]
    case "sacred_toggle_browser":
        var command: [String: Any] = ["cmd": "toggle-browser"]
        if let sessionID = optionalString(arguments, "session_id") { command["id"] = sessionID }
        if let open = arguments["open"] as? Bool { command["open"] = open }
        return command
    case "sacred_set_browser_url":
        return [
            "cmd": "set-browser-url",
            "id": try requiredString(arguments, "session_id"),
            "url": try requiredString(arguments, "url"),
        ]
    default:
        throw RPCError(-32602, "Unknown tool: \(toolName)")
    }
}

private func requiredString(_ object: [String: Any], _ key: String) throws -> String {
    guard let value = optionalString(object, key) else {
        throw RPCError(-32602, "Missing required string argument: \(key)")
    }
    return value
}

private func optionalString(_ object: [String: Any], _ key: String) -> String? {
    guard let value = object[key] as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func toolResult(reply: [String: Any], isError: Bool) -> [String: Any] {
    [
        "content": [
            [
                "type": "text",
                "text": jsonString(reply),
            ],
        ],
        "structuredContent": reply,
        "isError": isError,
    ]
}

private func jsonString(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return String(describing: object)
    }
    return string
}

private func objectSchema(properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
    var schema: [String: Any] = [
        "type": "object",
        "properties": properties,
        "additionalProperties": false,
    ]
    if !required.isEmpty {
        schema["required"] = required
    }
    return schema
}

private func stringSchema(_ description: String, allowed: [String]? = nil) -> [String: Any] {
    var schema: [String: Any] = [
        "type": "string",
        "description": description,
    ]
    if let allowed {
        schema["enum"] = allowed
    }
    return schema
}

private func boolSchema(_ description: String) -> [String: Any] {
    [
        "type": "boolean",
        "description": description,
    ]
}

SacredMCPServer().run()
