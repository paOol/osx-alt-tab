import AltTabCore
import AppKit
import ApplicationServices

/// Enumerates application windows — on-screen, minimized, hidden and on other
/// Spaces — and orders them most-recently-used first, the way Windows' Alt+Tab
/// does.
@MainActor
enum WindowEnumerator {

    /// Returns the current switchable windows in MRU order.
    static func list(filter: WindowFilter, focus: FocusTracker) -> [WindowInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let regularApps = Dictionary(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // `.optionAll` includes windows that are minimized, hidden or on other
        // Spaces. On-screen windows come first, front-to-back.
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        struct Candidate {
            let id: CGWindowID
            let pid: pid_t
            let bounds: CGRect
            let isOnscreen: Bool
        }

        var candidates: [Candidate] = []
        for dict in raw {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = dict[kCGWindowNumber as String] as? CGWindowID,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID, regularApps[pid] != nil else { continue }

            var bounds = CGRect.zero
            if let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
               let parsed = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                bounds = parsed
            }
            // Skip windows too small to be a real top-level window (sheets, popovers, shadows).
            if bounds.width < 80 || bounds.height < 80 { continue }

            let isOnscreen = dict[kCGWindowIsOnscreen as String] as? Bool ?? false
            candidates.append(Candidate(id: id, pid: pid, bounds: bounds, isOnscreen: isOnscreen))
        }

        // Map each pid to its AX windows once (keyed by CGWindowID) to avoid
        // re-querying the accessibility tree per window.
        var axByPID: [pid_t: [CGWindowID: AXUIElement]] = [:]
        var byID: [CGWindowID: WindowInfo] = [:]
        var switchableIDs: [CGWindowID] = []

        for candidate in candidates {
            if axByPID[candidate.pid] == nil {
                axByPID[candidate.pid] = axWindows(for: candidate.pid)
            }
            var axElement = axByPID[candidate.pid]?[candidate.id]
            if axElement == nil && !candidate.isOnscreen {
                // Probably on another Space: use the background cache, and
                // refresh it if this window isn't in there yet.
                axElement = OtherSpaceWindowFinder.shared.windows(for: candidate.pid)[candidate.id]
                if axElement == nil {
                    OtherSpaceWindowFinder.shared.scan(candidate.pid)
                }
            }
            // Off-screen candidates include lots of invisible helper windows,
            // so hold them to the strict test.
            guard let axElement,
                  candidate.isOnscreen ? axElement.isVisibleSwitchableWindow : axElement.isStandardWindow
            else { continue }
            switchableIDs.append(candidate.id)

            let app = regularApps[candidate.pid]
            let isMinimized = axElement.boolAttribute(kAXMinimizedAttribute) ?? false
            let isAppHidden = app?.isHidden ?? false
            let window = WindowInfo(
                id: candidate.id,
                pid: candidate.pid,
                axElement: axElement,
                appName: app?.localizedName ?? "Unknown",
                bundleID: app?.bundleIdentifier,
                title: axElement.stringAttribute(kAXTitleAttribute) ?? "",
                appIcon: app?.icon,
                bounds: candidate.bounds,
                isMinimized: isMinimized,
                isAppHidden: isAppHidden,
                isOnOtherSpace: !candidate.isOnscreen && !isMinimized && !isAppHidden
            )

            let traits = WindowTraits(
                bundleID: window.bundleID,
                appName: window.appName,
                bounds: window.bounds,
                isMinimized: window.isMinimized,
                isAppHidden: window.isAppHidden,
                isOnOtherSpace: window.isOnOtherSpace
            )
            if filter.includes(traits) {
                byID[candidate.id] = window
            }
        }

        // Order by the tracked MRU list; windows never seen focused fall back to
        // z-order (on-screen first) after the known ones. Reconcile against all
        // real windows, not just the filtered ones, so filters don't erase history.
        let order = focus.order(present: switchableIDs)
        return order.compactMap { byID[$0] }
    }

    /// All windows of an app on the current Space (including minimized ones),
    /// keyed by CGWindowID.
    private static func axWindows(for pid: pid_t) -> [CGWindowID: AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return [:]
        }

        var result: [CGWindowID: AXUIElement] = [:]
        for window in windows {
            if let id = window.cgWindowID {
                result[id] = window
            }
        }
        return result
    }
}
