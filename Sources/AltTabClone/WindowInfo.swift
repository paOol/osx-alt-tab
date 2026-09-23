import AppKit
import ApplicationServices

/// A single switchable window, as shown in the switcher overlay.
struct WindowInfo: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let axElement: AXUIElement
    let appName: String
    let bundleID: String?
    let title: String
    let appIcon: NSImage?
    /// Global display coordinates, top-left origin.
    let bounds: CGRect
    var isMinimized: Bool
    var isAppHidden: Bool
    var isOnOtherSpace: Bool

    /// Text shown under each item: prefer the window title, fall back to the app name.
    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    /// Header text: the app name alongside the title, so similar or untitled
    /// windows from different apps can be told apart.
    var headerTitle: String {
        title.isEmpty || title == appName ? appName : "\(appName) — \(title)"
    }

    /// Not currently visible, so a fresh thumbnail can't be captured.
    var isOffscreen: Bool {
        isMinimized || isAppHidden || isOnOtherSpace
    }
}
