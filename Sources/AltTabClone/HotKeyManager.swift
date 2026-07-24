import AppKit
import CoreGraphics

/// Intercepts the Alt(⌥)+Tab chord globally with a CGEventTap and drives the
/// switcher. Mirrors Windows semantics:
///   • ⌥+Tab          → open switcher / advance selection forward
///   • ⌥+Shift+Tab    → advance selection backward
///   • release ⌥      → commit (activate the selected window)
///   • Esc            → cancel
///
/// When `shouldPassThrough` says the frontmost app owns Alt+Tab (a remote-desktop
/// or VM client running another OS), the chord is forwarded untouched — except
/// for ⌃⌥+Tab, which always drives the local switcher as an escape hatch.
final class HotKeyManager {
    var onOpenOrNext: (() -> Void)?
    var onPrev: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    /// Consulted on every ⌥+Tab; return true to let the focused app have it.
    var shouldPassThrough: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isShowing = false

    private let tabKey: Int64 = 48
    private let escapeKey: Int64 = 53

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

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

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that's too slow or gets interrupted; re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let optionDown = flags.contains(.maskAlternate)
        let shiftDown = flags.contains(.maskShift)
        let controlDown = flags.contains(.maskControl)

        switch type {
        case .keyDown:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == tabKey && optionDown {
                // A remote session/VM is focused: the guest OS owns Alt+Tab.
                // ⌃⌥+Tab still opens the local switcher so fullscreen clients
                // can't trap you.
                if !isShowing && !controlDown && shouldPassThrough?() == true {
                    return Unmanaged.passUnretained(event)
                }
                if !isShowing {
                    isShowing = true
                    onOpenOrNext?()
                } else if shiftDown {
                    onPrev?()
                } else {
                    onOpenOrNext?()
                }
                return nil // swallow Tab so the focused app never sees it
            }
            if keycode == escapeKey && isShowing {
                isShowing = false
                onCancel?()
                return nil
            }

        case .flagsChanged:
            // Releasing Option while the switcher is up commits the selection.
            if isShowing && !optionDown {
                isShowing = false
                onCommit?()
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }
}
