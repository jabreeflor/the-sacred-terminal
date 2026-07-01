#!/usr/bin/env node
import net from "node:net";
import os from "node:os";
import path from "node:path";

const protocolVersion = "2025-03-26";
const supportedProtocolVersions = new Set(["2025-03-26", "2024-11-05"]);

const tools = [
  tool("sacred_get_state", "Read projects, sessions, panes, browser state, sidebar state, and available agents from the running app."),
  tool("sacred_list_sessions", "List sessions with their project, agent, task, and status."),
  tool("sacred_add_project", "Add a project folder to the rail, matching the Add Project UI action.", {
    path: stringSchema("Absolute folder path for the project."),
    name: stringSchema("Optional display name. Defaults to the folder name."),
  }, ["path"]),
  tool("sacred_toggle_sidebar", "Toggle the side rail, or set it open/closed when the open argument is provided.", {
    open: boolSchema("Optional target state for the side rail."),
  }),
  tool("sacred_toggle_project", "Collapse or expand a project row.", {
    project_id: stringSchema("Project id."),
  }, ["project_id"]),
  tool("sacred_create_session", "Create an agent-bound session under a project, matching the rail quick-pick or agent picker.", {
    project_id: stringSchema("Project id."),
    agent: stringSchema("Agent key.", ["claude", "codex", "cursor", "gemini", "copilot", "opencode", "shell"]),
    worktree: boolSchema("Whether the session should be marked as worktree-backed."),
  }, ["project_id", "agent"]),
  tool("sacred_focus_session", "Focus a session, matching a click on its rail row.", {
    session_id: stringSchema("Session id."),
  }, ["session_id"]),
  tool("sacred_close_session", "Close a session, matching the rail close button.", {
    session_id: stringSchema("Session id."),
  }, ["session_id"]),
  tool("sacred_send_to_session", "Send text to a session's app model, matching the send-to-agent interaction.", {
    session_id: stringSchema("Session id."),
    message: stringSchema("Message text."),
  }, ["session_id", "message"]),
  tool("sacred_set_session_status", "Set a session status so the rail and menu-bar state reflect the new status.", {
    session_id: stringSchema("Session id."),
    status: stringSchema("Status value.", ["working", "waiting", "idle", "done"]),
  }, ["session_id", "status"]),
  tool("sacred_add_pane", "Open a new terminal pane/tab in a session, matching the New Tab UI action.", {
    session_id: stringSchema("Session id."),
    kind: stringSchema("Pane kind.", ["shell", "agent"]),
  }, ["session_id"]),
  tool("sacred_split_pane", "Split the active or given session right/down, matching the split buttons and shortcuts.", {
    session_id: stringSchema("Optional session id. Defaults to the active session."),
    direction: stringSchema("Split direction.", ["right", "down", "horizontal", "vertical"]),
  }, ["direction"]),
  tool("sacred_focus_pane", "Focus a terminal pane/tab inside a session.", {
    session_id: stringSchema("Session id."),
    pane_id: stringSchema("Pane id."),
  }, ["session_id", "pane_id"]),
  tool("sacred_close_pane", "Close a terminal pane/tab inside a session.", {
    session_id: stringSchema("Session id."),
    pane_id: stringSchema("Pane id."),
  }, ["session_id", "pane_id"]),
  tool("sacred_toggle_browser", "Toggle or set the integrated browser for a session, matching the titlebar globe button.", {
    session_id: stringSchema("Optional session id. Defaults to the active session."),
    open: boolSchema("Optional target open state."),
  }),
  tool("sacred_set_browser_url", "Set the integrated browser URL for a session.", {
    session_id: stringSchema("Session id."),
    url: stringSchema("URL to load or store in the browser bar."),
  }, ["session_id", "url"]),
];

const toolNames = new Set(tools.map((item) => item.name));
let inputBuffer = Buffer.alloc(0);

process.stdin.on("data", (chunk) => {
  inputBuffer = Buffer.concat([inputBuffer, chunk]);
  drainFrames();
});

process.stdin.on("end", () => {
  drainFinalLine();
});

process.stdin.resume();

function drainFrames() {
  while (inputBuffer.length > 0) {
    const frame = nextFrame();
    if (!frame) return;
    handleFrame(frame.data, frame.framing);
  }
}

function drainFinalLine() {
  if (inputBuffer.length === 0 || startsWithContentLengthHeader(inputBuffer)) return;
  let line = inputBuffer;
  inputBuffer = Buffer.alloc(0);
  if (line.at(-1) === 0x0d) line = line.subarray(0, line.length - 1);
  handleFrame(line, "newline");
}

function nextFrame() {
  if (startsWithContentLengthHeader(inputBuffer)) {
    const separator = Buffer.from("\r\n\r\n");
    const headerEnd = inputBuffer.indexOf(separator);
    if (headerEnd === -1) return null;

    const header = inputBuffer.subarray(0, headerEnd).toString("utf8");
    const length = contentLength(header);
    if (length == null) return null;

    const bodyStart = headerEnd + separator.length;
    const bodyEnd = bodyStart + length;
    if (inputBuffer.length < bodyEnd) return null;

    const data = inputBuffer.subarray(bodyStart, bodyEnd);
    inputBuffer = inputBuffer.subarray(bodyEnd);
    return { data, framing: "content-length" };
  }

  const newline = inputBuffer.indexOf(0x0a);
  if (newline === -1) return null;

  let line = inputBuffer.subarray(0, newline);
  inputBuffer = inputBuffer.subarray(newline + 1);
  if (line.at(-1) === 0x0d) line = line.subarray(0, line.length - 1);
  return { data: line, framing: "newline" };
}

function startsWithContentLengthHeader(buffer) {
  return buffer.subarray(0, 14).toString("utf8").toLowerCase().startsWith("content-length");
}

function contentLength(header) {
  for (const line of header.split("\r\n")) {
    const index = line.indexOf(":");
    if (index === -1) continue;
    const key = line.slice(0, index).trim().toLowerCase();
    if (key !== "content-length") continue;
    const value = Number.parseInt(line.slice(index + 1).trim(), 10);
    return Number.isFinite(value) ? value : null;
  }
  return null;
}

async function handleFrame(data, framing) {
  if (data.length === 0) return;
  try {
    const message = JSON.parse(data.toString("utf8"));
    const response = await handleMessage(message);
    if (response != null) send(response, framing);
  } catch {
    send(errorResponse(null, -32700, "Parse error"), framing);
  }
}

async function handleMessage(message) {
  if (Array.isArray(message)) {
    const responses = [];
    for (const item of message) {
      const response = await handleMessage(item);
      if (response != null) responses.push(response);
    }
    return responses.length > 0 ? responses : null;
  }

  if (!message || typeof message !== "object") {
    return errorResponse(null, -32600, "Invalid request");
  }

  const hasId = Object.hasOwn(message, "id");
  const id = hasId ? message.id : null;
  if (typeof message.method !== "string") {
    return hasId ? errorResponse(id, -32600, "Invalid request") : null;
  }

  if (!hasId) return null;

  try {
    return {
      jsonrpc: "2.0",
      id,
      result: await handleRequest(message.method, message.params),
    };
  } catch (error) {
    return errorResponse(id, error.code ?? -32603, error.message ?? String(error));
  }
}

async function handleRequest(method, params) {
  switch (method) {
    case "initialize":
      return initialize(params);
    case "ping":
      return {};
    case "tools/list":
      return { tools };
    case "tools/call":
      return callTool(params);
    case "shutdown":
      return null;
    default:
      throw rpcError(-32601, `Method not found: ${method}`);
  }
}

function initialize(params) {
  const requested = params?.protocolVersion ?? protocolVersion;
  const selected = supportedProtocolVersions.has(requested) ? requested : protocolVersion;
  return {
    protocolVersion: selected,
    capabilities: { tools: { listChanged: false } },
    serverInfo: { name: "sacred-terminal-mcp", version: "0.1.0" },
    instructions: "Use these tools to drive the same Sacred Terminal workspace state that the AppKit UI reads and mutates.",
  };
}

async function callTool(params) {
  const name = params?.name;
  if (typeof name !== "string" || name.trim() === "") {
    throw rpcError(-32602, "tools/call requires a tool name");
  }
  if (!toolNames.has(name)) {
    throw rpcError(-32602, `Unknown tool: ${name}`);
  }

  const args = params?.arguments && typeof params.arguments === "object" ? params.arguments : {};
  const command = socketCommand(name, args);
  try {
    const reply = await requestApp(command);
    return toolResult(reply, reply.ok !== true);
  } catch (error) {
    return toolResult({ ok: false, error: error.message ?? String(error) }, true);
  }
}

function socketCommand(name, args) {
  switch (name) {
    case "sacred_get_state":
      return { cmd: "get-state" };
    case "sacred_list_sessions":
      return { cmd: "list-sessions" };
    case "sacred_add_project":
      return compact({ cmd: "add-project", path: requiredString(args, "path"), name: optionalString(args, "name") });
    case "sacred_toggle_sidebar":
      return typeof args.open === "boolean" ? { cmd: "set-sidebar", open: args.open } : { cmd: "toggle-sidebar" };
    case "sacred_toggle_project":
      return { cmd: "toggle-project", id: requiredString(args, "project_id") };
    case "sacred_create_session":
      return compact({
        cmd: "new-session",
        project: requiredString(args, "project_id"),
        agent: requiredString(args, "agent"),
        worktree: typeof args.worktree === "boolean" ? args.worktree : undefined,
      });
    case "sacred_focus_session":
      return { cmd: "focus", id: requiredString(args, "session_id") };
    case "sacred_close_session":
      return { cmd: "close-session", id: requiredString(args, "session_id") };
    case "sacred_send_to_session":
      return { cmd: "send", id: requiredString(args, "session_id"), message: requiredString(args, "message") };
    case "sacred_set_session_status":
      return { cmd: "set-status", id: requiredString(args, "session_id"), status: requiredString(args, "status") };
    case "sacred_add_pane":
      return compact({ cmd: "add-pane", id: requiredString(args, "session_id"), kind: optionalString(args, "kind") });
    case "sacred_split_pane":
      return compact({ cmd: "split-pane", id: optionalString(args, "session_id"), direction: requiredString(args, "direction") });
    case "sacred_focus_pane":
      return { cmd: "focus-pane", id: requiredString(args, "session_id"), pane: requiredString(args, "pane_id") };
    case "sacred_close_pane":
      return { cmd: "close-pane", id: requiredString(args, "session_id"), pane: requiredString(args, "pane_id") };
    case "sacred_toggle_browser":
      return compact({
        cmd: "toggle-browser",
        id: optionalString(args, "session_id"),
        open: typeof args.open === "boolean" ? args.open : undefined,
      });
    case "sacred_set_browser_url":
      return { cmd: "set-browser-url", id: requiredString(args, "session_id"), url: requiredString(args, "url") };
    default:
      throw rpcError(-32602, `Unknown tool: ${name}`);
  }
}

function requestApp(command) {
  const socketPath = controlSocketPath();
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    let buffer = "";

    socket.on("connect", () => {
      socket.write(`${JSON.stringify(command)}\n`);
    });
    socket.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      const newline = buffer.indexOf("\n");
      if (newline === -1) return;

      const line = buffer.slice(0, newline).replace(/\r$/, "");
      socket.end();
      try {
        resolve(JSON.parse(line));
      } catch {
        reject(new Error(`unexpected reply from app: ${line}`));
      }
    });
    socket.on("error", (error) => {
      if (error.code === "ENOENT" || error.code === "ECONNREFUSED") {
        reject(new Error(`The Sacred Terminal does not appear to be running (no socket at ${socketPath}). Launch the app first.`));
      } else {
        reject(error);
      }
    });
    socket.on("end", () => {
      if (buffer.length === 0) reject(new Error("connection closed before a reply was received"));
    });
  });
}

function controlSocketPath() {
  const override = process.env.SACRED_TERMINAL_APP_SUPPORT_DIR?.trim();
  if (override) return path.join(expandHome(override), "control.sock");
  return path.join(os.homedir(), "Library", "Application Support", "SacredTerminal", "control.sock");
}

function expandHome(value) {
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

function requiredString(args, key) {
  const value = optionalString(args, key);
  if (value == null) throw rpcError(-32602, `Missing required string argument: ${key}`);
  return value;
}

function optionalString(args, key) {
  const value = args[key];
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

function compact(object) {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined && value !== null));
}

function toolResult(reply, isError) {
  return {
    content: [{ type: "text", text: JSON.stringify(reply, null, 2) }],
    structuredContent: reply,
    isError,
  };
}

function send(object, framing) {
  const data = Buffer.from(JSON.stringify(object), "utf8");
  if (framing === "content-length") {
    process.stdout.write(`Content-Length: ${data.length}\r\n\r\n`);
    process.stdout.write(data);
  } else {
    process.stdout.write(data);
    process.stdout.write("\n");
  }
}

function errorResponse(id, code, message) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

function rpcError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function tool(name, description, properties = {}, required = []) {
  const inputSchema = { type: "object", properties, additionalProperties: false };
  if (required.length > 0) inputSchema.required = required;
  return { name, description, inputSchema };
}

function stringSchema(description, values) {
  const schema = { type: "string", description };
  if (values) schema.enum = values;
  return schema;
}

function boolSchema(description) {
  return { type: "boolean", description };
}
