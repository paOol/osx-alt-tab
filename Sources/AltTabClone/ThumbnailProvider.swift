import AppKit
import ScreenCaptureKit

/// Captures live previews of windows for the switcher using ScreenCaptureKit.
/// Requires Screen Recording permission; if unavailable, callers fall back to
/// the app icon so the switcher still works.
enum ThumbnailProvider {

    /// Capture thumbnails for the given window ids. Returns a map of id → image.
    /// Best-effort: ids that can't be captured are simply omitted.
    static func thumbnails(for windowIDs: [CGWindowID]) async -> [CGWindowID: NSImage] {
        guard !windowIDs.isEmpty else { return [:] }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ) else {
            return [:]
        }

        let wanted = Set(windowIDs)
        let targets = content.windows.filter { wanted.contains($0.windowID) }

        var result: [CGWindowID: NSImage] = [:]
        for scWindow in targets {
            if let image = await capture(scWindow) {
                result[scWindow.windowID] = image
            }
        }
        return result
    }

    private static func capture(_ window: SCWindow) async -> NSImage? {
        let config = SCStreamConfiguration()
        // Cap the capture size; thumbnails are small on screen anyway.
        let scale = 0.5
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false

        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        ) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
