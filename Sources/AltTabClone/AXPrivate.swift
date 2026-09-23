import ApplicationServices
import CoreGraphics
import Foundation

/// Private (but long-stable) AppKit/HIServices SPI that maps an Accessibility
/// element to its CoreGraphics window id. This is the only reliable way to
/// correlate the z-ordered list from `CGWindowListCopyWindowInfo` with the
/// `AXUIElement` window handles we need in order to raise a specific window.
///
/// Declared via `@_silgen_name` so we don't need a separate C bridging target.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Private SPI that builds an AX element from a raw remote token. The public
/// `kAXWindowsAttribute` only lists windows on the *current* Space; minting
/// tokens for an app's element ids is the known way to reach windows on other
/// Spaces (including fullscreen apps). Used by `OtherSpaceWindowFinder`.
@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

extension AXUIElement {
    /// The CoreGraphics window id backing this accessibility window element, if any.
    var cgWindowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success ? id : nil
    }

    func stringAttribute(_ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    func boolAttribute(_ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    func elementAttribute(_ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// True for real top-level windows (standard windows and dialogs), as
    /// opposed to floating palettes, popovers and invisible helper windows.
    var isStandardWindow: Bool {
        guard let subrole = stringAttribute(kAXSubroleAttribute) else { return false }
        return subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
    }

    /// Looser test for windows that are visibly on screen: some apps (Java,
    /// older Electron, games) report no or an unusual subrole for their main
    /// windows, so only rule out floating palettes.
    var isVisibleSwitchableWindow: Bool {
        guard stringAttribute(kAXRoleAttribute) == kAXWindowRole else { return false }
        let subrole = stringAttribute(kAXSubroleAttribute)
        return subrole != kAXFloatingWindowSubrole && subrole != kAXSystemFloatingWindowSubrole
    }
}

enum AXTimeouts {
    /// Cap how long any Accessibility request may block. The default is ~6s,
    /// so one hung app would otherwise freeze the switcher for that long.
    static func install() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
    }
}
