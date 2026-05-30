import AppKit
import CoreGraphics

/// Intercepts the Alt(⌥)+Tab chord globally with a CGEventTap and drives the
/// switcher. Mirrors Windows semantics:
///   • ⌥+Tab          → open switcher / advance selection forward
///   • ⌥+Shift+Tab    → advance selection backward
///   • release ⌥      → commit (activate the selected window)
///   • Esc            → cancel
final class HotKeyManager {
    var onOpenOrNext: (() -> Void)?
    var onPrev: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

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

        switch type {
        case .keyDown:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == tabKey && optionDown {
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
