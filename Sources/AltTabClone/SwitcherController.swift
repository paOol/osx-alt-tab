import AltTabCore
import AppKit
import SwiftUI

/// Owns the overlay panel and the switcher session lifecycle.
@MainActor
final class SwitcherController {
    /// Called whenever a session ends from this side (click, empty list,
    /// watchdog), so the input side can resync its state.
    var onSessionEnded: (() -> Void)?

    private let model = SwitcherModel()
    private let focus: FocusTracker
    private var panel: NSPanel?
    private var hosting: NSHostingController<SwitcherView>?
    private var screen: NSScreen?

    private var thumbnailTask: Task<Void, Never>?
    private var showWorkItem: DispatchWorkItem?
    private var watchdog: Timer?
    /// Last captured preview per window, shown instantly on the next open while
    /// fresh captures load (and kept for windows that can't be captured now).
    private var thumbnailCache: [CGWindowID: NSImage] = [:]

    /// True while a switching session is in progress.
    private(set) var isActive = false

    init(focus: FocusTracker) {
        self.focus = focus
    }

    func handle(_ command: SwitcherCommand) {
        switch command {
        case .open(let sameApp, let reverse):
            if isActive {
                advance(by: reverse ? -1 : 1)
            } else {
                begin(sameApp: sameApp, reverse: reverse)
            }
        case .next:
            advance(by: 1)
        case .previous:
            advance(by: -1)
        case .move(let direction):
            move(direction)
        case .commit:
            commit()
        case .cancel:
            cancel()
        case .action(let action):
            perform(action)
        }
    }

    // MARK: - Session control

    /// Commit the current selection and tear down the overlay.
    func commit() {
        guard isActive else { return }
        Log.switcher.debug("commit")
        let target = model.selectedWindow
        end()
        if let target {
            WindowActivator.activate(target, focus: focus)
        }
    }

    /// Dismiss without switching.
    func cancel() {
        guard isActive else { return }
        Log.switcher.debug("cancel")
        end()
    }

    private func begin(sameApp: Bool, reverse: Bool) {
        let settings = Settings.load()
        let screen = screenUnderMouse()
        self.screen = screen

        focus.noteFrontmostWindow()

        var filter = WindowFilter()
        filter.showMinimized = settings.showMinimized
        filter.showHidden = settings.showHidden
        filter.showOtherSpaces = settings.showOtherSpaces
        filter.excluded = AppMatcher(patterns: settings.excludedApps)
        if settings.currentScreenOnly, let screen {
            filter.screenBounds = Self.globalCGRect(for: screen.frame)
        }

        var windows = WindowEnumerator.list(filter: filter, focus: focus)
        if sameApp, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            windows = windows.filter { $0.pid == pid }
        }
        Log.switcher.debug("open: \(windows.count, privacy: .public) windows (sameApp: \(sameApp, privacy: .public))")
        guard !windows.isEmpty else {
            onSessionEnded?()
            return
        }

        let present = Set(windows.map(\.id))
        thumbnailCache = thumbnailCache.filter { present.contains($0.key) }

        model.itemSize = CGSize(width: settings.thumbnailWidth, height: (settings.thumbnailWidth * 0.65).rounded())
        configureGrid(for: screen)
        model.windows = windows
        model.thumbnails = thumbnailCache
        model.selected = Selection.initial(count: windows.count, reverse: reverse)
        model.resetHover()
        isActive = true

        loadThumbnails(for: windows, scale: screen?.backingScaleFactor ?? 2)
        startWatchdog()

        // Hold off on showing the panel so a quick flip doesn't flash it.
        if settings.showDelay > 0 {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.showPanel() }
            }
            showWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.showDelay, execute: work)
        } else {
            showPanel()
        }
    }

    private func advance(by delta: Int) {
        guard isActive else { return }
        model.selected = Selection.step(model.selected, by: delta, count: model.windows.count)
        // Cycling means the user wants to see the list; don't wait out the delay.
        showPanel()
    }

    private func move(_ direction: SwitcherCommand.Direction) {
        guard isActive else { return }
        let columns = max(1, min(model.columns, model.windows.count))
        switch direction {
        case .left: model.selected = Selection.step(model.selected, by: -1, count: model.windows.count)
        case .right: model.selected = Selection.step(model.selected, by: 1, count: model.windows.count)
        case .up: model.selected = Selection.moveRow(model.selected, by: -1, columns: columns, count: model.windows.count)
        case .down: model.selected = Selection.moveRow(model.selected, by: 1, columns: columns, count: model.windows.count)
        }
        showPanel()
    }

    private func perform(_ action: WindowAction) {
        guard isActive, let window = model.selectedWindow else { return }
        switch action {
        case .close:
            WindowActivator.close(window)
            model.windows.removeAll { $0.id == window.id }
        case .quit:
            WindowActivator.quit(pid: window.pid)
            model.windows.removeAll { $0.pid == window.pid }
        case .minimize:
            let minimize = !window.isMinimized
            WindowActivator.setMinimized(window, minimize)
            model.windows[model.selected].isMinimized = minimize
            model.windows[model.selected].isOnOtherSpace = false
        case .hide:
            let hidden = WindowActivator.toggleHidden(pid: window.pid)
            for index in model.windows.indices where model.windows[index].pid == window.pid {
                model.windows[index].isAppHidden = hidden
            }
        }

        guard !model.windows.isEmpty else {
            cancel()
            onSessionEnded?()
            return
        }
        model.selected = min(model.selected, model.windows.count - 1)
        showPanel()
    }

    private func end() {
        isActive = false
        showWorkItem?.cancel()
        showWorkItem = nil
        watchdog?.invalidate()
        watchdog = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        panel?.orderOut(nil)
    }

    /// If the ⌥ release was missed (event tap disabled, secure input, focus
    /// changes mid-session) the overlay would otherwise stay up forever. Poll
    /// the real modifier state and finish the session the way a release would.
    ///
    /// A normal release is handled instantly by the event tap; this is only the
    /// fallback, so it waits for several consecutive "released" readings
    /// rather than risk switching windows on a single bad one.
    private func startWatchdog() {
        watchdog?.invalidate()
        var releasedPolls = 0
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                let optionHeld = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
                releasedPolls = optionHeld ? 0 : releasedPolls + 1
                if releasedPolls >= 3 {
                    Log.switcher.debug("watchdog: ⌥ no longer held, committing")
                    self.onSessionEnded?()
                    self.commit()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func loadThumbnails(for windows: [WindowInfo], scale: CGFloat) {
        thumbnailTask?.cancel()
        // Minimized windows can't be captured; keep their cached preview.
        let ids = windows.filter { !$0.isMinimized }.map(\.id)
        let maxPixelSize = CGSize(width: model.itemSize.width * scale, height: model.itemSize.height * scale)
        thumbnailTask = Task { [weak self] in
            let images = await ThumbnailProvider.thumbnails(for: ids, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled, !images.isEmpty, let self else { return }
            self.thumbnailCache.merge(images) { _, new in new }
            self.model.thumbnails.merge(images) { _, new in new }
        }
    }

    // MARK: - Panel

    /// Fit as many columns/rows as the screen allows.
    private func configureGrid(for screen: NSScreen?) {
        let visible = screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let cell = SwitcherView.cellSize(for: model.itemSize)
        let spacing = SwitcherView.spacing
        let chrome: CGFloat = 48 // panel padding
        let headerHeight: CGFloat = 34
        let availableWidth = visible.width * 0.9 - chrome
        let availableHeight = visible.height * 0.8 - chrome - headerHeight
        model.columns = max(1, Int((availableWidth + spacing) / (cell.width + spacing)))
        model.maxVisibleRows = max(1, Int((availableHeight + spacing) / (cell.height + spacing)))
    }

    private func showPanel() {
        guard isActive else { return }
        showWorkItem?.cancel()
        showWorkItem = nil

        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Size to the current content (the window count changes per session
        // and after actions), then center on the session's screen.
        // (The hosting view's `fittingSize` is zero with automatic sizing off,
        // so ask SwiftUI for the content's ideal size directly.)
        if let hosting {
            let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            let size = hosting.sizeThatFits(in: unbounded)
            panel.setContentSize(size)
            Log.switcher.debug("panel size \(size.width, privacy: .public)x\(size.height, privacy: .public)")
        }
        if let screen = screen ?? screenUnderMouse() {
            let size = panel.frame.size
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.midY - size.height / 2).rounded()
            ))
        }

        if !panel.isVisible {
            model.resetHover()
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(
            rootView: SwitcherView(model: model) { [weak self] index in
                guard let self else { return }
                self.model.selected = index
                self.onSessionEnded?()
                self.commit()
            }
        )
        // We size the panel ourselves in `showPanel`.
        hosting.sizingOptions = []
        self.hosting = hosting

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
        return panel
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Convert an AppKit screen rect (bottom-left origin) to the global
    /// CoreGraphics space (top-left origin of the primary display) that window
    /// bounds use.
    private static func globalCGRect(for frame: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
