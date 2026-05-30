import AppKit
import ApplicationServices

/// Brings a chosen window to the foreground: raises the specific window and
/// activates its owning application so it receives keyboard focus.
enum WindowActivator {
    static func activate(_ window: WindowInfo) {
        // Un-minimize if needed, then raise the specific window within its app.
        AXUIElementSetAttributeValue(window.axElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window.axElement, kAXMainAttribute as CFString, kCFBooleanTrue)

        // Activate the app so the raised window actually gets keyboard focus.
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate()
        }

        WindowEnumerator.markUsed(window.id)
    }
}
