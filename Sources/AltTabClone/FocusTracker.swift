import AltTabCore
import AppKit
import ApplicationServices

/// Maintains the most-recently-used window order by watching focus changes
/// system-wide — app activations and focused-window changes inside apps — so
/// switching via ⌘+Tab, a click, the Dock or Mission Control keeps the quick
/// ⌥+Tab flip target correct, not only switches made through this app.
@MainActor
final class FocusTracker {
    private var mru = MRUList<CGWindowID>()
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    func start() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app.processIdentifier)
        }

        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.activationPolicy == .regular else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated { self.observe(pid) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated { self.stopObserving(pid) }
                OtherSpaceWindowFinder.shared.forget(pid)
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated { self.noteFocusedWindow(of: pid) }
            },
            // Windows on the Space we just left are now unreachable through the
            // public AX API; refresh the fallback cache while nobody's waiting.
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
                for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                    OtherSpaceWindowFinder.shared.scan(app.processIdentifier)
                }
                MainActor.assumeIsolated { self.noteFrontmostWindow() }
            },
        ]

        noteFrontmostWindow()
    }

    /// Record that a window was just focused.
    func touch(_ windowID: CGWindowID) {
        mru.touch(windowID)
    }

    /// The MRU order restricted to `present` windows (front-to-back z-order),
    /// with never-seen windows appended in z-order.
    func order(present: [CGWindowID]) -> [CGWindowID] {
        mru.reconcile(present: present)
        return mru.order
    }

    /// Safety net used when a session opens, in case a notification was missed.
    func noteFrontmostWindow() {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            noteFocusedWindow(of: pid)
        }
    }

    private func noteFocusedWindow(of pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        if let window = app.elementAttribute(kAXFocusedWindowAttribute), let id = window.cgWindowID {
            touch(id)
        }
    }

    // MARK: - Per-app AX observers

    private func observe(_ pid: pid_t, attempt: Int = 0) {
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { tracker.focusChanged(to: element) }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, app, kAXMainWindowChangedNotification as CFString, refcon)

        guard result == .success else {
            // A freshly launched app often isn't ready for AX yet; try again shortly.
            if attempt < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated { self.observe(pid, attempt: attempt + 1) }
                }
            }
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    private func stopObserving(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func focusChanged(to element: AXUIElement) {
        // Background apps shuffle their own focus too; only the frontmost app's
        // focus reflects what the user is looking at.
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              pid == NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let id = element.cgWindowID else { return }
        touch(id)
    }
}
