import AppKit
import ApplicationServices

/// A single switchable window, as shown in the switcher overlay.
struct WindowInfo: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let axElement: AXUIElement
    let appName: String
    let title: String
    let appIcon: NSImage?
    var thumbnail: NSImage?

    /// Text shown under each item: prefer the window title, fall back to the app name.
    var displayTitle: String {
        title.isEmpty ? appName : title
    }
}
