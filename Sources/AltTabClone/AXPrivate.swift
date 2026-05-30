import ApplicationServices
import CoreGraphics

/// Private (but long-stable) AppKit/HIServices SPI that maps an Accessibility
/// element to its CoreGraphics window id. This is the only reliable way to
/// correlate the z-ordered list from `CGWindowListCopyWindowInfo` with the
/// `AXUIElement` window handles we need in order to raise a specific window.
///
/// Declared via `@_silgen_name` so we don't need a separate C bridging target.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    /// The CoreGraphics window id backing this accessibility window element, if any.
    var cgWindowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success ? id : nil
    }
}
