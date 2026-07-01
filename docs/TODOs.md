# TODOs

## Publish MCP Package To npm

Current MCP setup uses the GitHub repo as the `npx` package specifier:

```json
{
  "command": "npx",
  "args": ["-y", "github:jabreeflor/the-sacred-terminal"]
}
```

This is acceptable for now, but it is a temporary distribution path. Publish the MCP package to npm so client configuration can become:

```json
{
  "command": "npx",
  "args": ["-y", "sacred-terminal-mcp"]
}
```

Notes:

- Keep the Node-based MCP entrypoint as the default setup path.
- Confirm the package name before publishing.
- Update `docs/mcp/setup.md` after the package is available on npm.
