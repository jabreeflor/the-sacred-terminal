# Sacred Terminal MCP Setup

This repo includes an `npx`-runnable stdio MCP server for driving a running Sacred Terminal app through the same Unix socket control surface used by the `sacred` CLI.

The MCP server itself is Node-based. You do not need to build the Swift MCP target to use it.

## Run The App

The MCP server talks to the app over `control.sock`, so Sacred Terminal must be running before MCP tools can mutate app state.

```bash
cd macos/SacredTerminal
swift run SacredTerminal
```

For a packaged app:

```bash
cd macos/SacredTerminal
./scripts/package-app.sh
open .build/SacredTerminal.app
```

## Configure An MCP Client

Use `npx` as the stdio MCP command.

```json
{
  "mcpServers": {
    "sacred-terminal": {
      "command": "npx",
      "args": ["-y", "github:jabreeflor/the-sacred-terminal"]
    }
  }
}
```

For local development from a checkout, point `npx` at the repo directory:

```json
{
  "mcpServers": {
    "sacred-terminal": {
      "command": "npx",
      "args": ["-y", "/absolute/path/to/the-sacred-terminal"]
    }
  }
}
```

If your client starts from a different environment or you want an isolated app state, pass the same app-support directory to both Sacred Terminal and the MCP server:

```json
{
  "mcpServers": {
    "sacred-terminal": {
      "command": "npx",
      "args": ["-y", "github:jabreeflor/the-sacred-terminal"],
      "env": {
        "SACRED_TERMINAL_APP_SUPPORT_DIR": "/tmp/sacred-terminal-dev"
      }
    }
  }
}
```

When this env var is unset, the app and MCP server use:

```text
~/Library/Application Support/SacredTerminal/control.sock
```

## Available Tools

The server exposes tools that map app UI interactions into actual app socket commands:

| Tool | UI Equivalent |
|---|---|
| `sacred_get_state` | Read projects, sessions, panes, sidebar, browser state, and agent roster |
| `sacred_list_sessions` | List rail sessions |
| `sacred_add_project` | Rail add project |
| `sacred_toggle_sidebar` | Titlebar sidebar toggle |
| `sacred_toggle_project` | Project row collapse/expand |
| `sacred_create_session` | Rail quick-pick / agent picker session creation |
| `sacred_focus_session` | Click a rail session |
| `sacred_close_session` | Rail session close |
| `sacred_send_to_session` | Send text to a session model |
| `sacred_set_session_status` | Update the status reflected in rail/menu-bar state |
| `sacred_add_pane` | Workspace new tab |
| `sacred_split_pane` | Workspace split right/down |
| `sacred_focus_pane` | Click a terminal tab/pane |
| `sacred_close_pane` | Close a terminal tab/pane |
| `sacred_toggle_browser` | Titlebar browser toggle |
| `sacred_set_browser_url` | Browser URL bar update |

## Smoke Test

From the repo root, check the server handshake manually:

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"manual","version":"1"}}}' \
  | npx -y .
```

You should receive a JSON-RPC response containing:

```json
{
  "protocolVersion": "2025-03-26",
  "serverInfo": {
    "name": "sacred-terminal-mcp"
  }
}
```

## Troubleshooting

- If a tool returns `The Sacred Terminal does not appear to be running`, launch the app first.
- If the app is running but tools still cannot connect, make sure the MCP server and app agree on `SACRED_TERMINAL_APP_SUPPORT_DIR`.
- If `npx` cannot find the package from GitHub, use the local checkout form: `npx -y /absolute/path/to/the-sacred-terminal`.
- If your MCP client requires Content-Length framing, the Node server supports it; newline-delimited JSON-RPC also works for local smoke tests.
