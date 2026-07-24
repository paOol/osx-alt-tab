import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = SwitcherController()
    private let hotKeys = HotKeyManager()
    private let passthrough = PassthroughPolicy()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard ensureAccessibilityPermission() else {
            // The trust prompt has been shown; the user must grant access and relaunch.
            presentPermissionGuidance()
            return
        }

        passthrough.start()
        wireHotKeys()

        if !hotKeys.start() {
            presentAlert(
                title: "Couldn't start AltTabClone",
                message: "Failed to install the keyboard event tap. Make sure AltTabClone has Accessibility permission in System Settings → Privacy & Security → Accessibility, then relaunch."
            )
        }

        // Warm up Screen Recording permission so thumbnails work on first use.
        CGRequestScreenCaptureAccess()
    }

    private func wireHotKeys() {
        hotKeys.shouldPassThrough = { [weak self] in
            self?.passthrough.shouldPassThrough() ?? false
        }
        hotKeys.onOpenOrNext = { [weak self] in
            Task { @MainActor in self?.switcher.openOrNext() }
        }
        hotKeys.onPrev = { [weak self] in
            Task { @MainActor in self?.switcher.previous() }
        }
        hotKeys.onCommit = { [weak self] in
            Task { @MainActor in self?.switcher.commit() }
        }
        hotKeys.onCancel = { [weak self] in
            Task { @MainActor in self?.switcher.cancel() }
        }
    }

    // MARK: - Permissions

    private func ensureAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func presentPermissionGuidance() {
        presentAlert(
            title: "Accessibility permission needed",
            message: "AltTabClone needs Accessibility access to switch windows.\n\nGrant it in System Settings → Privacy & Security → Accessibility, then relaunch AltTabClone."
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
    }
}
