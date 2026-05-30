import AppKit
import SwiftUI

/// Owns the overlay panel and the switcher session lifecycle.
@MainActor
final class SwitcherController {
    private let model = SwitcherModel()
    private var panel: NSPanel?
    private var thumbnailTask: Task<Void, Never>?

    /// True while a switching session is in progress.
    private(set) var isActive = false

    // MARK: - Session control

    /// Open the switcher (selecting the previous window) or, if already open,
    /// advance the selection forward — exactly like repeated Alt+Tab presses.
    func openOrNext() {
        if isActive {
            advance(by: 1)
        } else {
            begin()
        }
    }

    func previous() {
        guard isActive else { return }
        advance(by: -1)
    }

    /// Commit the current selection and tear down the overlay.
    func commit() {
        guard isActive else { return }
        let target = model.selectedWindow
        end()
        if let target {
            WindowActivator.activate(target)
        }
    }

    /// Dismiss without switching.
    func cancel() {
        guard isActive else { return }
        end()
    }

    // MARK: - Internals

    private func begin() {
        let windows = WindowEnumerator.list()
        guard !windows.isEmpty else { return }

        model.windows = windows
        // Default to the previous window (index 1) so a quick tap flips back,
        // matching Windows. With a single window, stay on it.
        model.selected = windows.count > 1 ? 1 : 0

        showPanel()
        loadThumbnails(for: windows.map(\.id))
        isActive = true
    }

    private func advance(by delta: Int) {
        guard !model.windows.isEmpty else { return }
        let count = model.windows.count
        model.selected = ((model.selected + delta) % count + count) % count
    }

    private func end() {
        isActive = false
        thumbnailTask?.cancel()
        thumbnailTask = nil
        panel?.orderOut(nil)
    }

    private func loadThumbnails(for ids: [CGWindowID]) {
        thumbnailTask?.cancel()
        thumbnailTask = Task { [model] in
            let images = await ThumbnailProvider.thumbnails(for: ids)
            if Task.isCancelled { return }
            await MainActor.run { model.updateThumbnails(images) }
        }
    }

    // MARK: - Panel

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Center on the screen containing the mouse.
        if let screen = screenUnderMouse() {
            panel.layoutIfNeeded()
            let panelSize = panel.frame.size
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - panelSize.width / 2,
                y: visible.midY - panelSize.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(
            rootView: SwitcherView(model: model) { [weak self] index in
                guard let self else { return }
                self.model.selected = index
                self.commit()
            }
        )

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // Let the panel size itself to the SwiftUI content.
        panel.setContentSize(hosting.view.fittingSize)
        return panel
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
