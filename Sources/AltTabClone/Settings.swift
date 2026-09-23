import Foundation

/// User preferences, stored in the app's defaults domain and re-read at the
/// start of every switcher session, so `defaults write` changes apply
/// immediately — no relaunch.
///
///     defaults write com.alttabclone.app ShowOtherSpaces -bool false
///     defaults write com.alttabclone.app ExcludedApps -array finder
///
/// See the README for the full list.
struct Settings {
    static let passthroughEnabledKey = "PassthroughEnabled"
    static let passthroughAppsKey = "PassthroughApps"

    /// Include minimized windows (badged) in the switcher.
    var showMinimized = true
    /// Include windows of apps hidden with ⌘H (badged).
    var showHidden = true
    /// Include windows on other Spaces, including fullscreen apps (badged).
    var showOtherSpaces = true
    /// Only show windows on the screen containing the mouse.
    var currentScreenOnly = false
    /// Apps never shown in the switcher (substring of bundle id or name).
    var excludedApps: [String] = []
    /// How long ⌥ must be held before the overlay appears. A quick ⌥+Tab flip
    /// shorter than this switches without flashing the panel.
    var showDelay: TimeInterval = 0.12
    /// Width of each thumbnail, in points.
    var thumbnailWidth: CGFloat = 200
    /// ⌥+` cycles through the frontmost app's windows only.
    var sameAppShortcut = true

    static func load(from defaults: UserDefaults = .standard) -> Settings {
        var settings = Settings()
        if let value = defaults.object(forKey: "ShowMinimizedWindows") as? Bool { settings.showMinimized = value }
        if let value = defaults.object(forKey: "ShowHiddenApps") as? Bool { settings.showHidden = value }
        if let value = defaults.object(forKey: "ShowOtherSpaces") as? Bool { settings.showOtherSpaces = value }
        if let value = defaults.object(forKey: "CurrentScreenOnly") as? Bool { settings.currentScreenOnly = value }
        if let value = defaults.stringArray(forKey: "ExcludedApps") { settings.excludedApps = value }
        if let value = defaults.object(forKey: "ShowDelayMilliseconds") as? Double {
            settings.showDelay = max(0, value) / 1000
        }
        if let value = defaults.object(forKey: "ThumbnailWidth") as? Double {
            settings.thumbnailWidth = CGFloat(min(max(value, 80), 600))
        }
        if let value = defaults.object(forKey: "SameAppShortcut") as? Bool { settings.sameAppShortcut = value }
        return settings
    }
}
