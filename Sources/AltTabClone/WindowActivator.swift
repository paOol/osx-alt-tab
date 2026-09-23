import AppKit
import ApplicationServices

/// Brings a chosen window to the foreground and performs the in-switcher
/// window actions (close, minimize, hide, quit).
@MainActor
enum WindowActivator {
    static func activate(_ window: WindowInfo, focus: FocusTracker) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        if app?.isHidden == true {
            app?.unhide()
        }
        if window.axElement.boolAttribute(kAXMinimizedAttribute) == true {
            AXUIElementSetAttributeValue(window.axElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        // Make the app frontmost through Accessibility first. Unlike
        // `NSRunningApplication.activate()`, this isn't subject to macOS 14's
        // cooperative activation, which can refuse requests from an app (like
        // this one) that never holds focus itself.
        let appElement = AXUIElementCreateApplication(window.pid)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)

        // Then raise the specific window, after the app is in front, so the
        // app doesn't bring its own key window over it.
        AXUIElementSetAttributeValue(window.axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        app?.activate()

        // Some apps re-raise their previous key window as activation completes;
        // raise ours once more after that settles.
        let element = window.axElement
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }

        focus.touch(window.id)
    }

    /// Press the window's close button (so apps can still prompt to save).
    static func close(_ window: WindowInfo) {
        if let button = window.axElement.elementAttribute(kAXCloseButtonAttribute) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    static func setMinimized(_ window: WindowInfo, _ minimized: Bool) {
        AXUIElementSetAttributeValue(
            window.axElement,
            kAXMinimizedAttribute as CFString,
            minimized ? kCFBooleanTrue : kCFBooleanFalse
        )
    }

    /// Toggle whether the window's app is hidden; returns the new hidden state.
    static func toggleHidden(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if app.isHidden {
            app.unhide()
            return false
        }
        app.hide()
        return true
    }

    static func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }
}
