import AppKit
import ScreenCaptureKit

/// Captures previews of windows for the switcher using ScreenCaptureKit.
/// Requires Screen Recording permission; if unavailable, callers fall back to
/// the app icon so the switcher still works.
enum ThumbnailProvider {

    /// Capture thumbnails for the given window ids, in parallel, each sized to
    /// fit `maxPixelSize`. Best-effort: ids that can't be captured are omitted.
    static func thumbnails(for windowIDs: [CGWindowID], maxPixelSize: CGSize) async -> [CGWindowID: NSImage] {
        // Never trigger a permission prompt from the hot path.
        guard !windowIDs.isEmpty, CGPreflightScreenCaptureAccess() else { return [:] }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ) else {
            return [:]
        }

        let wanted = Set(windowIDs)
        let targets = content.windows.filter { wanted.contains($0.windowID) }

        return await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
            for scWindow in targets {
                group.addTask {
                    (scWindow.windowID, await capture(scWindow, maxPixelSize: maxPixelSize))
                }
            }
            var result: [CGWindowID: NSImage] = [:]
            for await (id, image) in group {
                if let image { result[id] = image }
            }
            return result
        }
    }

    private static func capture(_ window: SCWindow, maxPixelSize: CGSize) async -> NSImage? {
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { return nil }

        // Capture at the size it will be displayed (never upscaled): cheaper
        // than full resolution and sharper than a fixed fraction of it.
        let scale = min(1, maxPixelSize.width / frame.width, maxPixelSize.height / frame.height)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(frame.width * scale))
        config.height = max(1, Int(frame.height * scale))
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
