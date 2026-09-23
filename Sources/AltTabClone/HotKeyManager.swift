import AppKit
import CoreGraphics

/// Intercepts the Alt(⌥)+Tab chord globally with a CGEventTap and drives the
/// switcher. Mirrors Windows semantics:
///   • ⌥+Tab          → open switcher / advance selection forward
///   • ⌥+Shift+Tab    → open on the last window / advance backward
///   • ⌥+`            → same, limited to the frontmost app's windows
///   • release ⌥      → commit (activate the selected window)
///   • Esc            → cancel
/// While the switcher is open every other key is swallowed so nothing leaks to
/// the app underneath; arrows/Return/W/M/H/Q drive the switcher instead.
///
/// When `shouldPassThrough` says the frontmost app owns Alt+Tab (a remote-desktop
/// or VM client running another OS), the chord is forwarded untouched — except
/// for ⌃⌥+Tab, which always drives the local switcher as an escape hatch.
///
/// The tap runs on its own thread so a busy main thread (enumerating windows,
/// talking to an unresponsive app) can never add latency to system-wide typing
/// or get the tap disabled by the system's timeout.
final class HotKeyManager: @unchecked Sendable {
    /// Delivered on the main thread, in order.
    var onCommand: ((SwitcherCommand) -> Void)?

    /// Consulted on every ⌥+Tab (on the tap thread); return true to let the
    /// focused app have it.
    var shouldPassThrough: (() -> Bool)?

    /// Consulted on ⌥+` (on the tap thread).
    var sameAppShortcutEnabled: (() -> Bool)?

    private var eventTap: CFMachPort?

    /// Session state shared between the tap thread and the main thread.
    private let lock = NSLock()
    private var isShowing = false
    /// Keys whose keyDown we swallowed; their keyUp is swallowed too so apps
    /// never see an unmatched key-up.
    private var swallowedKeyUps: Set<Int64> = []

    private enum Key {
        static let tab: Int64 = 48
        static let grave: Int64 = 50
        static let escape: Int64 = 53
        static let returnKey: Int64 = 36
        static let keypadEnter: Int64 = 76
        static let left: Int64 = 123
        static let right: Int64 = 124
        static let down: Int64 = 125
        static let up: Int64 = 126
    }

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "AltTabClone.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    /// The switcher ended on its own (click, empty list, watchdog). Resync so
    /// the next ⌥ release or Tab isn't interpreted as part of a dead session.
    func sessionEnded() {
        lock.lock()
        isShowing = false
        lock.unlock()
    }

    // MARK: - Tap thread

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that's too slow or gets interrupted; re-arm
        // it, and if ⌥ was released while we were deaf, finish that session.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            let optionHeld = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
            if !optionHeld && endSessionIfShowing() {
                send(.commit)
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let optionDown = flags.contains(.maskAlternate)
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .keyDown:
            return handleKeyDown(keycode: keycode, flags: flags, event: event)

        case .keyUp:
            lock.lock()
            let swallowed = swallowedKeyUps.remove(keycode) != nil
            lock.unlock()
            return swallowed ? nil : Unmanaged.passUnretained(event)

        case .flagsChanged:
            // Releasing Option while the switcher is up commits the selection.
            if !optionDown && endSessionIfShowing() {
                send(.commit)
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(keycode: Int64, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>? {
        let optionDown = flags.contains(.maskAlternate)
        let shiftDown = flags.contains(.maskShift)
        let controlDown = flags.contains(.maskControl)

        lock.lock()
        let showing = isShowing
        lock.unlock()

        guard showing else {
            let isTab = keycode == Key.tab
            let isGrave = keycode == Key.grave && sameAppShortcutEnabled?() == true
            guard optionDown, !flags.contains(.maskCommand), isTab || isGrave else {
                return Unmanaged.passUnretained(event)
            }
            // A remote session/VM is focused: the guest OS owns Alt+Tab.
            // ⌃⌥+Tab still opens the local switcher so fullscreen clients
            // can't trap you.
            if !controlDown && shouldPassThrough?() == true {
                return Unmanaged.passUnretained(event)
            }
            lock.lock()
            isShowing = true
            swallowedKeyUps.insert(keycode)
            lock.unlock()
            send(.open(sameApp: isGrave, reverse: shiftDown))
            return nil // swallow so the focused app never sees it
        }

        // Session in progress: every key belongs to the switcher.
        lock.lock()
        swallowedKeyUps.insert(keycode)
        lock.unlock()

        switch keycode {
        case Key.tab, Key.grave:
            send(shiftDown ? .previous : .next)
        case Key.escape:
            if endSessionIfShowing() { send(.cancel) }
        case Key.returnKey, Key.keypadEnter:
            if endSessionIfShowing() { send(.commit) }
        case Key.left:
            send(.move(.left))
        case Key.right:
            send(.move(.right))
        case Key.up:
            send(.move(.up))
        case Key.down:
            send(.move(.down))
        default:
            // Letters are matched by character, not keycode, so they follow the
            // active keyboard layout (AZERTY, Dvorak, …).
            switch NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased() {
            case "w": send(.action(.close))
            case "m": send(.action(.minimize))
            case "h": send(.action(.hide))
            case "q": send(.action(.quit))
            default: break
            }
        }
        return nil
    }

    /// Atomically end the session; true if one was in progress.
    private func endSessionIfShowing() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isShowing else { return false }
        isShowing = false
        return true
    }

    private func send(_ command: SwitcherCommand) {
        DispatchQueue.main.async { [weak self] in
            self?.onCommand?(command)
        }
    }
}
