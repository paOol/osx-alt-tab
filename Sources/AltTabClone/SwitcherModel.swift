import AppKit
import SwiftUI

/// Observable state backing the switcher overlay.
@MainActor
final class SwitcherModel: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selected: Int = 0
    /// Kept apart from `windows` so a thumbnail arriving doesn't rebuild the list.
    @Published var thumbnails: [CGWindowID: NSImage] = [:]

    /// Grid layout for the current session.
    var itemSize = CGSize(width: 200, height: 130)
    var columns = 5
    var maxVisibleRows = 3

    /// Where the mouse was when the session opened. Hover only selects once
    /// the mouse has actually moved, so a panel appearing under a stationary
    /// pointer doesn't steal the quick-flip selection.
    var mouseOrigin: NSPoint = .zero
    private var mouseHasMoved = false

    var selectedWindow: WindowInfo? {
        windows.indices.contains(selected) ? windows[selected] : nil
    }

    func resetHover() {
        mouseOrigin = NSEvent.mouseLocation
        mouseHasMoved = false
    }

    func hover(_ index: Int) {
        if !mouseHasMoved {
            let now = NSEvent.mouseLocation
            mouseHasMoved = hypot(now.x - mouseOrigin.x, now.y - mouseOrigin.y) > 3
        }
        if mouseHasMoved && windows.indices.contains(index) {
            selected = index
        }
    }
}
