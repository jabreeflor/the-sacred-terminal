import AppKit
import SacredTerminalSupport

/// E2E-only programmatic UI driver exposed through the existing control socket.
///
/// This is intentionally not available in normal app launches. It gives tests a
/// tool-like way to press the same AppKit controls a user would click, while also
/// validating the control's center-point hit-test before dispatching the action.
enum E2EUIDriver {
    static func canHandle(_ command: String) -> Bool {
        switch command {
        case "ui-state", "ui-hit-test", "ui-press", "ui-smoke-session-tabs":
            return true
        default:
            return false
        }
    }

    static func handle(command: String, object: [String: Any]) -> [String: Any] {
        guard SacredTerminalRuntime.isE2EMode else {
            return ["ok": false, "error": "\(command) is only available when \(SacredTerminalRuntime.e2eModeEnv)=1"]
        }

        switch command {
        case "ui-state":
            return ["ok": true, "state": stateObject()]

        case "ui-hit-test":
            guard let identifier = nonEmptyString(object["id"]) else {
                return ["ok": false, "error": "ui-hit-test requires \"id\""]
            }
            return hitTest(identifier: identifier)

        case "ui-press":
            guard let identifier = nonEmptyString(object["id"]) else {
                return ["ok": false, "error": "ui-press requires \"id\""]
            }
            return press(identifier: identifier)

        case "ui-smoke-session-tabs":
            return smokeSessionAndTabSwitching()

        default:
            return ["ok": false, "error": "unknown E2E UI command \"\(command)\""]
        }
    }

    // MARK: - Actions

    private static func press(identifier: String) -> [String: Any] {
        guard let located = locateView(identifier: identifier) else {
            return ["ok": false, "error": "no view \"\(identifier)\""]
        }
        guard let hit = hitTestResult(for: located.view) else {
            return ["ok": false, "error": "could not hit-test \"\(identifier)\""]
        }
        let hitMatchesTarget = hit.hitView === located.view
        if requiresExactHitTarget(identifier), !hitMatchesTarget {
            return [
                "ok": false,
                "error": "center of \"\(identifier)\" hit \(describe(hit.hitView)) instead",
                "target": describe(located.view),
                "hit": describe(hit.hitView),
                "point": pointObject(hit.pointInWindow),
                "pointInTarget": pointObject(hit.pointInTarget),
            ]
        }

        if let button = located.view as? NSButton {
            button.performClick(nil)
        } else if !located.view.accessibilityPerformPress() {
            return ["ok": false, "error": "\"\(identifier)\" does not support press"]
        }

        return [
            "ok": true,
            "pressed": identifier,
            "hit": describe(hit.hitView),
            "hitMatchesTarget": hitMatchesTarget,
            "state": stateObject(),
        ]
    }

    private static func hitTest(identifier: String) -> [String: Any] {
        guard let located = locateView(identifier: identifier) else {
            return ["ok": false, "error": "no view \"\(identifier)\""]
        }
        guard let hit = hitTestResult(for: located.view) else {
            return ["ok": false, "error": "could not hit-test \"\(identifier)\""]
        }
        return [
            "ok": true,
            "target": describe(located.view),
            "hit": describe(hit.hitView),
            "matchesTarget": hit.hitView === located.view,
            "hitInsideTarget": hit.hitView.isDescendant(of: located.view),
            "point": pointObject(hit.pointInWindow),
            "pointInTarget": pointObject(hit.pointInTarget),
        ]
    }

    private static func smokeSessionAndTabSwitching() -> [String: Any] {
        let sessions = AppState.shared.allSessions
        guard sessions.count >= 2 else {
            return ["ok": false, "error": "ui-smoke-session-tabs requires at least two sessions"]
        }

        let first = sessions[0].session
        let second = sessions[1].session
        let firstPane = first.activePaneID
        let initialPaneCount = first.panes.count
        var steps: [[String: Any]] = []

        if let error = pressForSmoke("session-row-\(second.id)", steps: &steps) { return error }
        guard AppState.shared.activeSessionID == second.id else {
            return smokeFailure("second session did not become active", steps: steps)
        }

        if let error = pressForSmoke("session-row-\(first.id)", steps: &steps) { return error }
        guard AppState.shared.activeSessionID == first.id else {
            return smokeFailure("first session did not become active again", steps: steps)
        }

        if let error = pressForSmoke("workspace-new-tab", steps: &steps) { return error }
        guard first.panes.count == initialPaneCount + 1 else {
            return smokeFailure("new tab did not add a pane to the first session", steps: steps)
        }
        let newPane = first.activePaneID
        guard newPane != firstPane else {
            return smokeFailure("new tab did not become the active pane", steps: steps)
        }

        if let error = pressForSmoke("workspace-tab-\(firstPane)", steps: &steps) { return error }
        guard first.activePaneID == firstPane else {
            return smokeFailure("first terminal tab did not become active", steps: steps)
        }

        if let error = pressForSmoke("workspace-tab-\(newPane)", steps: &steps) { return error }
        guard first.activePaneID == newPane else {
            return smokeFailure("new terminal tab did not become active again", steps: steps)
        }

        return ["ok": true, "steps": steps, "state": stateObject()]
    }

    private static func pressForSmoke(_ identifier: String, steps: inout [[String: Any]]) -> [String: Any]? {
        let reply = press(identifier: identifier)
        steps.append([
            "press": identifier,
            "ok": reply["ok"] as? Bool ?? false,
            "error": reply["error"] as? String ?? "",
        ])
        if reply["ok"] as? Bool == true { return nil }
        return [
            "ok": false,
            "error": "smoke failed pressing \(identifier): \((reply["error"] as? String) ?? "unknown error")",
            "steps": steps,
            "state": stateObject(),
        ]
    }

    private static func smokeFailure(_ message: String, steps: [[String: Any]]) -> [String: Any] {
        ["ok": false, "error": message, "steps": steps, "state": stateObject()]
    }

    // MARK: - Hit testing

    private struct LocatedView {
        let view: NSView
    }

    private struct HitTestResult {
        let hitView: NSView
        let pointInWindow: NSPoint
        let pointInTarget: NSPoint
    }

    private static func locateView(identifier: String) -> LocatedView? {
        for window in NSApp.windows {
            window.contentView?.layoutSubtreeIfNeeded()
            guard let root = window.contentView else { continue }
            if let view = firstView(in: root, matching: identifier) {
                return LocatedView(view: view)
            }
        }
        return nil
    }

    private static func firstView(in root: NSView, matching identifier: String) -> NSView? {
        if viewIdentifier(root) == identifier { return root }
        for subview in root.subviews.reversed() {
            if let match = firstView(in: subview, matching: identifier) {
                return match
            }
        }
        return nil
    }

    private static func hitTestResult(for view: NSView) -> HitTestResult? {
        guard let window = view.window, let contentView = window.contentView else { return nil }
        window.layoutIfNeeded()
        contentView.layoutSubtreeIfNeeded()

        let rectInWindow = view.convert(view.bounds, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)
        let pointInScreen = NSPoint(x: rectInScreen.midX, y: rectInScreen.midY)
        let pointInWindow = window.convertPoint(fromScreen: pointInScreen)
        let pointInContent = contentView.convert(pointInWindow, from: nil)
        let pointInTarget = view.convert(pointInContent, from: contentView)
        guard let hitView = contentView.hitTest(pointInContent) else { return nil }
        return HitTestResult(hitView: hitView,
                             pointInWindow: pointInWindow,
                             pointInTarget: pointInTarget)
    }

    // MARK: - State / descriptions

    private static func stateObject() -> [String: Any] {
        let state = AppState.shared
        return [
            "activeSessionID": state.activeSessionID ?? NSNull(),
            "projects": state.projects.map { project in
                [
                    "id": project.id,
                    "name": project.name,
                    "collapsed": project.collapsed,
                    "sessions": project.sessions.map { session in
                        [
                            "id": session.id,
                            "agent": session.agent.rawValue,
                            "task": session.task,
                            "status": session.status.rawValue,
                            "activePaneID": session.activePaneID,
                            "panes": session.panes.map { pane in
                                [
                                    "id": pane.id,
                                    "title": pane.title,
                                    "kind": pane.kind.rawValue,
                                    "started": pane.started,
                                ] as [String: Any]
                            },
                        ] as [String: Any]
                    },
                ] as [String: Any]
            },
        ]
    }

    private static func describe(_ view: NSView) -> [String: Any] {
        var object: [String: Any] = [
            "class": String(describing: type(of: view)),
            "identifier": viewIdentifier(view) ?? "",
            "bounds": rectObject(view.bounds),
        ]
        if let window = view.window {
            let rectInWindow = view.convert(view.bounds, to: nil)
            let rectInScreen = window.convertToScreen(rectInWindow)
            object["frame"] = rectObject(rectInScreen)
        }
        return object
    }

    private static func viewIdentifier(_ view: NSView) -> String? {
        if let identifier = view.identifier?.rawValue, !identifier.isEmpty {
            return identifier
        }
        let accessibilityIdentifier = view.accessibilityIdentifier()
        if !accessibilityIdentifier.isEmpty {
            return accessibilityIdentifier
        }
        return nil
    }

    private static func rectObject(_ rect: NSRect) -> [String: Double] {
        [
            "x": Double(rect.origin.x),
            "y": Double(rect.origin.y),
            "width": Double(rect.width),
            "height": Double(rect.height),
        ]
    }

    private static func pointObject(_ point: NSPoint) -> [String: Double] {
        ["x": Double(point.x), "y": Double(point.y)]
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func requiresExactHitTarget(_ identifier: String) -> Bool {
        identifier.hasPrefix("session-row-") || identifier.hasPrefix("project-row-")
    }
}
