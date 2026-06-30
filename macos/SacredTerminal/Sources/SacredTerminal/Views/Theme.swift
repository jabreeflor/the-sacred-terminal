import AppKit

/// App-chrome tokens (the cmux near-black shell around the Ghostty surfaces).
/// The terminal colors themselves come from Ghostty's config (spec §9), not here.
enum Theme {
    static func hex(_ s: String) -> NSColor {
        var h = s.hasPrefix("#") ? String(s.dropFirst()) : s
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let v = UInt32(h, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                       green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    static let chromeBg   = hex("#0c0c0e")
    static let railBg     = hex("#0a0a0c")
    static let titlebarBg = hex("#131316")
    static let panelBg    = hex("#0e0e11")
    static let border     = hex("#1c1c20")
    static let text       = hex("#e6e6ea")
    static let textDim    = hex("#8a8a93")
    static let textFaint  = hex("#5b5b63")
    static let hover      = hex("#16161a")
    static let accent     = hex("#1d6ef5")
    static let sessionActive = hex("#fab387")   // peach accent (status / pins)
    // Active-session row — the mock's subtle peach fill + border (NOT a blue fill):
    //   --session-active-bg: rgba(250,179,135,.06); --session-active-border: …,.45
    static let sessionActiveBg     = sessionActive.withAlphaComponent(0.06)
    static let sessionActiveBorder = sessionActive.withAlphaComponent(0.45)

    // Live rail colors — driven by Settings → Appearance (so the color pickers
    // actually re-theme the rail). Fall back to the defaults above.
    static var railBgLive: NSColor { hex(AppState.shared.appearance.railBg) }
    static var railFgLive: NSColor { hex(AppState.shared.appearance.railFg) }
    static var sessionHighlightLive: NSColor { hex(AppState.shared.appearance.sessionHighlight) }
    static var sessionActiveBgLive: NSColor { sessionHighlightLive.withAlphaComponent(0.06) }
    static var sessionActiveBorderLive: NSColor { sessionHighlightLive.withAlphaComponent(0.45) }
    static let pickerBg   = hex("#141417")      // floating panels (picker / settings / menus)
    static let pickerLine = hex("#2a2a30")
    static let hairlineSoft = hex("#222228")    // mock border-bottom for tab bars / toolbars
    static let browserUrlBg = hex("#0d0d10")    // mock .browser-url field bg
    static let terminalBg = hex("#303446")      // Catppuccin Frappé bg (until surface paints)

    static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    static let monoSmall = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    /// Brand icon for an agent, loaded from the bundled Resources/Icons.
    static func agentImage(_ key: AgentKey) -> NSImage? {
        let name = Agents.def(key).icon
        if let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Icons")
            ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Icons"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = false
            return img
        }
        return nil
    }
}
