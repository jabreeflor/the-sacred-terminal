import Foundation
import SacredTerminalSupport

/// Full workspace + settings snapshot, persisted so layout and sessions restore
/// across restarts — cmux's `AppSessionSnapshot` model (spec §10, §11).
struct AppSessionSnapshot: Codable {
    var projects: [Project]
    var activeSessionID: String?
    var sidebarOpen: Bool
    var agentEnabled: [AgentKey]
    var pinnedAgents: [AgentKey]
    var agentSettings: AgentSettings
    var appearance: AppearanceSettings
    var git: GitSettings
}

enum Persistence {
    static func load() -> AppSessionSnapshot? {
        guard let data = try? Data(contentsOf: SacredTerminalRuntime.sessionFileURL) else { return nil }
        return try? JSONDecoder().decode(AppSessionSnapshot.self, from: data)
    }

    static func save(_ snapshot: AppSessionSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        guard (try? SacredTerminalRuntime.ensureAppSupportDirectory()) != nil else { return }
        try? data.write(to: SacredTerminalRuntime.sessionFileURL, options: .atomic)
    }
}
