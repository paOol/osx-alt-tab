import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let focus = FocusTracker()
    private lazy var switcher = SwitcherController(focus: focus)
    private let hotKeys = HotKeyManager()
    private let passthrough = PassthroughPolicy()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AXTimeouts.install()

        if AXIsProcessTrusted() {
            start()
        } else {
            Log.app.info("waiting for Accessibility permission")
            waitForAccessibilityPermission()
        }
    }

    private func start() {
        passthrough.start()
        focus.start()
        wireHotKeys()

        let tapStarted = hotKeys.start()
        Log.app.info("started; event tap \(tapStarted ? "installed" : "FAILED", privacy: .public)")
        if !tapStarted {
            presentAlert(
                title: "Couldn't start AltTabClone",
                message: "Failed to install the keyboard event tap. Make sure AltTabClone has Accessibility permission in System Settings → Privacy & Security → Accessibility, then relaunch."
            )
            return
        }

        // Ask for Screen Recording (thumbnails) once; later launches don't re-prompt.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    private func wireHotKeys() {
        hotKeys.shouldPassThrough = { [passthrough] in
            passthrough.shouldPassThrough()
        }
        hotKeys.sameAppShortcutEnabled = {
            Settings.load().sameAppShortcut
        }
        hotKeys.onCommand = { [weak self] command in
            MainActor.assumeIsolated { self?.switcher.handle(command) }
        }
        switcher.onSessionEnded = { [hotKeys] in
            hotKeys.sessionEnded()
        }
    }

    // MARK: - Permissions

    /// Show the system prompt plus our guidance, then poll until access is
    /// granted and start on our own — no relaunch needed.
    private func waitForAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            MainActor.assumeIsolated {
                self?.permissionTimer = nil
                // Dismiss the guidance alert if it's still up.
                if NSApp.modalWindow != nil {
                    NSApp.abortModal()
                }
                self?.start()
            }
        }
        // `.common` includes the modal panel mode, so this keeps firing while
        // the alert below is on screen.
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer

        presentAlert(
            title: "Accessibility permission needed",
            message: "AltTabClone needs Accessibility access to switch windows.\n\nGrant it in System Settings → Privacy & Security → Accessibility. AltTabClone will start automatically once access is granted."
        )
    }

    private func presentAlert(title: String, message: String) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        // Back to a Dock-less agent once the alert is gone.
        NSApp.setActivationPolicy(.accessory)
    }
}
