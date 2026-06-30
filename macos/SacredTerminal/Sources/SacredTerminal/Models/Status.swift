import AppKit

/// Drives the rail dot color, label, and pulse (spec §8).
enum Status: String, Codable {
    case working, waiting, idle, done
}

struct StatusMeta {
    let label: String
    let color: NSColor
    let pulse: Bool
}

/// Single source of truth for status treatment (spec §8). The rail dots, the
/// tab spinners, and the menu-bar pulse all read from here.
func statusMeta(_ status: Status) -> StatusMeta {
    switch status {
    case .working: return StatusMeta(label: "Working",     color: NSColor(srgbRed: 0.65, green: 0.82, blue: 0.54, alpha: 1), pulse: true)   // #a6d189
    case .waiting: return StatusMeta(label: "Needs input", color: NSColor(srgbRed: 0.90, green: 0.78, blue: 0.56, alpha: 1), pulse: true)   // #e5c890
    case .done:    return StatusMeta(label: "Done",        color: NSColor(srgbRed: 0.55, green: 0.67, blue: 0.93, alpha: 1), pulse: false)  // #8caaee
    case .idle:    return StatusMeta(label: "Idle",        color: NSColor(srgbRed: 0.36, green: 0.36, blue: 0.39, alpha: 1), pulse: false)  // #5b5b63
    }
}
