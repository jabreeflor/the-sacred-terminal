import Foundation
import GhosttyKit

/// Maps libghostty surface handles → live `GhosttySurface` wrappers so the
/// runtime `action_cb` can request redraws without a CVDisplayLink per pane.
final class GhosttySurfaceRegistry {
    static let shared = GhosttySurfaceRegistry()

    private var surfaces: [UnsafeRawPointer: WeakBox] = [:]
    private let lock = NSLock()

    private final class WeakBox {
        weak var value: GhosttySurface?
        init(_ value: GhosttySurface) { self.value = value }
    }

    func register(_ handle: ghostty_surface_t?, _ surface: GhosttySurface) {
        guard let handle else { return }
        lock.lock()
        surfaces[UnsafeRawPointer(handle)] = WeakBox(surface)
        lock.unlock()
    }

    func unregister(_ handle: ghostty_surface_t?) {
        guard let handle else { return }
        lock.lock()
        surfaces.removeValue(forKey: UnsafeRawPointer(handle))
        lock.unlock()
    }

    func draw(_ handle: ghostty_surface_t?) {
        guard let handle else { return }
        lock.lock()
        let surface = surfaces[UnsafeRawPointer(handle)]?.value
        lock.unlock()
        surface?.draw()
    }
}
