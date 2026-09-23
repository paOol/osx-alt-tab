import ApplicationServices
import Foundation

/// Finds AX handles for windows that live on other Spaces (including
/// fullscreen apps), which `kAXWindowsAttribute` doesn't report.
///
/// The lookup brute-forces an app's AX element ids, which is too slow for the
/// ⌥+Tab hot path, so it runs on a background queue and results are cached:
/// the enumerator asks for a scan when it sees a window it can't match, and the
/// window shows up from the next ⌥+Tab on. Space switches trigger a rescan so
/// the cache is usually warm before it's needed.
final class OtherSpaceWindowFinder: @unchecked Sendable {
    static let shared = OtherSpaceWindowFinder()

    private let queue = DispatchQueue(label: "AltTabClone.OtherSpaceWindowFinder", qos: .userInitiated)
    private let lock = NSLock()
    private var cache: [pid_t: [CGWindowID: AXUIElement]] = [:]
    private var lastScan: [pid_t: Date] = [:]
    private var inFlight: Set<pid_t> = []

    /// Don't rescan an app more often than this.
    private let minimumRescanInterval: TimeInterval = 30

    /// Cached windows for `pid` (possibly stale; callers match by window id).
    func windows(for pid: pid_t) -> [CGWindowID: AXUIElement] {
        lock.lock()
        defer { lock.unlock() }
        return cache[pid] ?? [:]
    }

    /// Scan `pid` in the background unless it was scanned recently.
    func scan(_ pid: pid_t) {
        lock.lock()
        let recent = lastScan[pid].map { Date().timeIntervalSince($0) < minimumRescanInterval } ?? false
        guard !inFlight.contains(pid), !recent else {
            lock.unlock()
            return
        }
        inFlight.insert(pid)
        lock.unlock()

        queue.async { [self] in
            let found = Self.bruteForceWindows(pid: pid)
            lock.lock()
            cache[pid] = found
            lastScan[pid] = Date()
            inFlight.remove(pid)
            lock.unlock()
        }
    }

    func forget(_ pid: pid_t) {
        lock.lock()
        cache[pid] = nil
        lastScan[pid] = nil
        lock.unlock()
    }

    /// Mint AX elements for element ids 0..<1000 of `pid` and keep the ones that
    /// are real windows. Token layout (20 bytes): pid, 0, 'coco', element id.
    private static func bruteForceWindows(pid: pid_t) -> [CGWindowID: AXUIElement] {
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })

        let deadline = Date().addingTimeInterval(0.5)
        var result: [CGWindowID: AXUIElement] = [:]
        for elementID in UInt64(0)..<1000 {
            if Date() > deadline { break }
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue(),
                  element.isStandardWindow,
                  let windowID = element.cgWindowID else { continue }
            result[windowID] = element
        }
        return result
    }
}
