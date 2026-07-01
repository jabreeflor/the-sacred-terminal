import Foundation

public enum SacredTerminalRuntime {
    public static let appSupportDirectoryEnv = "SACRED_TERMINAL_APP_SUPPORT_DIR"
    public static let e2eModeEnv = "SACRED_TERMINAL_E2E"
    public static let disableGhosttySurfacesEnv = "SACRED_TERMINAL_DISABLE_GHOSTTY_SURFACES"
    public static let skipShellPathImportEnv = "SACRED_TERMINAL_SKIP_SHELL_PATH_IMPORT"

    public static var appSupportDirectory: URL {
        if let override = nonEmptyEnvironmentValue(appSupportDirectoryEnv) {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("SacredTerminal", isDirectory: true)
    }

    public static var sessionFileURL: URL {
        appSupportDirectory.appendingPathComponent("session.json")
    }

    public static var controlSocketURL: URL {
        appSupportDirectory.appendingPathComponent("control.sock")
    }

    @discardableResult
    public static func ensureAppSupportDirectory() throws -> URL {
        let directory = appSupportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static var isE2EMode: Bool {
        truthyEnvironmentValue(e2eModeEnv)
    }

    public static var shouldDisableGhosttySurfaces: Bool {
        truthyEnvironmentValue(disableGhosttySurfacesEnv)
    }

    public static var shouldSkipShellPathImport: Bool {
        isE2EMode || truthyEnvironmentValue(skipShellPathImportEnv)
    }

    private static func nonEmptyEnvironmentValue(_ key: String) -> String? {
        guard let raw = ProcessInfo.processInfo.environment[key] else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func truthyEnvironmentValue(_ key: String) -> Bool {
        guard let raw = nonEmptyEnvironmentValue(key)?.lowercased() else { return false }
        return !["0", "false", "no", "off"].contains(raw)
    }
}
