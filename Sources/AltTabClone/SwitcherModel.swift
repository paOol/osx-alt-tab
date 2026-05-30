import AppKit
import SwiftUI

/// Observable state backing the switcher overlay.
final class SwitcherModel: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selected: Int = 0

    var selectedWindow: WindowInfo? {
        windows.indices.contains(selected) ? windows[selected] : nil
    }

    func updateThumbnails(_ images: [CGWindowID: NSImage]) {
        guard !images.isEmpty else { return }
        for index in windows.indices {
            if let image = images[windows[index].id] {
                windows[index].thumbnail = image
            }
        }
        // Reassign to trigger SwiftUI update (WindowInfo is a value type).
        windows = windows
    }
}
