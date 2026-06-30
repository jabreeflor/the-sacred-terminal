import Foundation

/// The CLI that drives a session (spec §4, §7).
enum AgentKey: String, Codable, CaseIterable, Hashable {
    case claude, codex, cursor, gemini, copilot, opencode, shell
}

struct AgentDef {
    let name: String
    let provider: String
    /// Base launch command (resolved against PATH; falls back to a shell).
    let command: String
    /// Permission-bypass flag appended when YOLO mode is on (spec §7).
    let yoloFlag: String?
    /// Brand icon asset name in Resources/Icons.
    let icon: String
}

enum Agents {
    static let roster: [AgentKey: AgentDef] = [
        .claude:   AgentDef(name: "Claude Code",  provider: "Anthropic · Opus 4.8", command: "claude",       yoloFlag: "--dangerously-skip-permissions", icon: "claude"),
        .codex:    AgentDef(name: "Codex",        provider: "OpenAI · gpt-5",       command: "codex",        yoloFlag: "--dangerously-bypass-approvals-and-sandbox", icon: "codex"),
        .cursor:   AgentDef(name: "Cursor Agent", provider: "Cursor CLI",           command: "cursor-agent", yoloFlag: "--yolo", icon: "cursor"),
        .gemini:   AgentDef(name: "Gemini",       provider: "Google · 2.5 Pro",     command: "gemini",       yoloFlag: "--yolo", icon: "gemini"),
        .copilot:  AgentDef(name: "Copilot",      provider: "GitHub",               command: "copilot",      yoloFlag: nil, icon: "copilot"),
        .opencode: AgentDef(name: "OpenCode",     provider: "open source",          command: "opencode",     yoloFlag: nil, icon: "opencode"),
        .shell:    AgentDef(name: "Shell",        provider: "zsh",                  command: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh", yoloFlag: nil, icon: "shell"),
    ]

    static let order: [AgentKey] = [.claude, .codex, .cursor, .gemini, .copilot, .opencode, .shell]
    static let maxPinned = 6
    static let defaultPinned: [AgentKey] = [.opencode, .cursor, .gemini, .codex, .claude]

    static func def(_ key: AgentKey) -> AgentDef { roster[key] ?? roster[.shell]! }

    /// Argument vector handed to the Ghostty surface's `command` (it owns the PTY).
    static func launchArgv(_ key: AgentKey, yolo: Bool) -> [String] {
        let d = def(key)
        var argv = [d.command]
        if yolo, let flag = d.yoloFlag { argv.append(flag) }
        return argv
    }

    static func launchPreview(_ key: AgentKey, yolo: Bool) -> String {
        launchArgv(key, yolo: yolo).joined(separator: " ")
    }
}
