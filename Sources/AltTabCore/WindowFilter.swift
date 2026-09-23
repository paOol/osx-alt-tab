import CoreGraphics

/// What the filter needs to know about a candidate window.
public struct WindowTraits {
    public var bundleID: String?
    public var appName: String?
    /// Global display coordinates (top-left origin, as CoreGraphics reports them).
    public var bounds: CGRect
    public var isMinimized: Bool
    public var isAppHidden: Bool
    public var isOnOtherSpace: Bool

    public init(
        bundleID: String?,
        appName: String?,
        bounds: CGRect,
        isMinimized: Bool = false,
        isAppHidden: Bool = false,
        isOnOtherSpace: Bool = false
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.bounds = bounds
        self.isMinimized = isMinimized
        self.isAppHidden = isAppHidden
        self.isOnOtherSpace = isOnOtherSpace
    }
}

/// Decides which windows appear in the switcher.
public struct WindowFilter {
    public var showMinimized = true
    public var showHidden = true
    public var showOtherSpaces = true
    /// When set, only windows whose center lies on this screen are shown
    /// (same coordinate space as `WindowTraits.bounds`).
    public var screenBounds: CGRect?
    public var excluded = AppMatcher(patterns: [])

    public init() {}

    public func includes(_ window: WindowTraits) -> Bool {
        if excluded.matches(bundleID: window.bundleID, name: window.appName) { return false }
        if window.isMinimized && !showMinimized { return false }
        if window.isAppHidden && !showHidden { return false }
        if window.isOnOtherSpace && !showOtherSpaces { return false }
        if let screenBounds, !screenBounds.contains(CGPoint(x: window.bounds.midX, y: window.bounds.midY)) {
            return false
        }
        return true
    }
}
