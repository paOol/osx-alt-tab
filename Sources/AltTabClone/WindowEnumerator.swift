import AppKit
import ApplicationServices

/// Enumerates on-screen application windows and orders them
/// most-recently-used first, the way Windows' Alt+Tab does.
enum WindowEnumerator {

    /// Most-recently-used window-id order, newest first. Seeded from z-order and
    /// then maintained as the user switches windows so the second-most-recent
    /// window (index 1) is the default Alt+Tab target.
    private static var mruOrder: [CGWindowID] = []

    /// Record that a window was just focused, moving it to the front of the MRU list.
    static func markUsed(_ windowID: CGWindowID) {
        mruOrder.removeAll { $0 == windowID }
        mruOrder.insert(windowID, at: 0)
    }

    /// Returns the current switchable windows in MRU order.
    static func list() -> [WindowInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // CGWindowListCopyWindowInfo returns windows front-to-back. Collect the
        // normal-layer windows along with their owning pid, preserving that z-order.
        var zOrdered: [(id: CGWindowID, pid: pid_t)] = []
        for dict in raw {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = dict[kCGWindowNumber as String] as? CGWindowID,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID else { continue }

            // Skip windows too small to be a real top-level window (sheets, popovers, shadows).
            if let bounds = dict[kCGWindowBounds as String] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"], w < 80 || h < 80 {
                continue
            }
            zOrdered.append((id, pid))
        }

        // Map each pid to its AX windows once (keyed by CGWindowID) to avoid
        // re-querying the accessibility tree per window.
        var axByPID: [pid_t: [CGWindowID: AXUIElement]] = [:]
        let runningByPID = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var byID: [CGWindowID: WindowInfo] = [:]
        for entry in zOrdered {
            if axByPID[entry.pid] == nil {
                axByPID[entry.pid] = axWindows(for: entry.pid)
            }
            guard let axElement = axByPID[entry.pid]?[entry.id] else { continue }

            let app = runningByPID[entry.pid]
            let appName = app?.localizedName ?? "Unknown"
            let title = axElement.stringAttribute(kAXTitleAttribute) ?? ""

            byID[entry.id] = WindowInfo(
                id: entry.id,
                pid: entry.pid,
                axElement: axElement,
                appName: appName,
                title: title,
                appIcon: app?.icon,
                thumbnail: nil
            )
        }

        // Order by our maintained MRU list; any window not yet seen falls back to
        // z-order. Then prune MRU ids that no longer exist.
        let zOrder = zOrdered.map(\.id)
        reconcileMRU(present: zOrder)

        let ordered = mruOrder.compactMap { byID[$0] }
        return ordered
    }

    /// Merge freshly seen windows into the MRU list (new ones appended in z-order)
    /// and drop windows that have since closed.
    private static func reconcileMRU(present: [CGWindowID]) {
        let presentSet = Set(present)
        mruOrder.removeAll { !presentSet.contains($0) }
        for id in present where !mruOrder.contains(id) {
            mruOrder.append(id)
        }
    }

    /// All on-screen, non-minimized windows of an app, keyed by CGWindowID.
    private static func axWindows(for pid: pid_t) -> [CGWindowID: AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return [:]
        }

        var result: [CGWindowID: AXUIElement] = [:]
        for window in windows {
            // Skip minimized windows — they aren't in the on-screen CGWindowList anyway.
            if window.boolAttribute(kAXMinimizedAttribute) == true { continue }
            if let id = window.cgWindowID {
                result[id] = window
            }
        }
        return result
    }
}

// MARK: - AXUIElement attribute helpers

extension AXUIElement {
    func stringAttribute(_ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    func boolAttribute(_ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return (value as? Bool)
    }
}
