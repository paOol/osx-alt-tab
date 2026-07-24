import AppKit

/// Decides when the switcher should step aside and let the frontmost app receive
/// ⌥+Tab itself.
///
/// Remote-desktop and VM clients (Moonlight, Parsec, RDP, Parallels, …) run a
/// whole other OS inside their window; there, Alt+Tab belongs to the *guest*
/// session, not to macOS. While such a client is frontmost the event tap passes
/// the chord straight through. As soon as it quits or focus moves elsewhere the
/// local switcher takes over again — no mode to toggle.
///
/// The list is overridable:
///
///     defaults write com.alttabclone.app PassthroughApps -array moonlight parsec
///     defaults write com.alttabclone.app PassthroughEnabled -bool false
///
/// Entries are matched case-insensitively as substrings of the frontmost app's
/// bundle identifier *or* its name, so a bare "moonlight" is enough.
/// `@unchecked Sendable`: the mutable frontmost-app cache is lock-protected, and
/// everything else is immutable after `init`.
final class PassthroughPolicy: @unchecked Sendable {
    static let enabledKey = "PassthroughEnabled"
    static let appsKey = "PassthroughApps"

    /// Shipping defaults: the common streaming / remote-desktop / VM clients.
    static let defaultApps: [String] = [
        "moonlight",
        "parsec",
        "com.microsoft.rdc",       // Microsoft Remote Desktop
        "com.teamviewer",
        "com.anydesk",
        "chromeremotedesktop",
        "vmware",
        "com.parallels",
        "org.virtualbox",
        "com.utmapp.UTM",
        "steam remote play",
        "vnc",
    ]

    private let lock = NSLock()
    private var frontmostBundleID = ""
    private var frontmostName = ""
    private var observer: NSObjectProtocol?

    private let enabled: Bool
    private let needles: [String]

    init(defaults: UserDefaults = .standard) {
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let configured = defaults.stringArray(forKey: Self.appsKey) ?? Self.defaultApps
        needles = configured.map { $0.lowercased() }.filter { !$0.isEmpty }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Start tracking the frontmost application. Must be called on the main thread.
    @MainActor
    func start() {
        update(with: NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.update(with: app)
        }
    }

    /// True when ⌥+Tab should be forwarded to the frontmost app untouched.
    ///
    /// Called from the event-tap callback, hence the lock around the cached
    /// identity rather than a `NSWorkspace` lookup on the input hot path.
    func shouldPassThrough() -> Bool {
        guard enabled, !needles.isEmpty else { return false }
        lock.lock()
        let bundleID = frontmostBundleID
        let name = frontmostName
        lock.unlock()
        guard !bundleID.isEmpty || !name.isEmpty else { return false }
        return needles.contains { bundleID.contains($0) || name.contains($0) }
    }

    /// Name of the frontmost app, for logging/diagnostics.
    var frontmostDescription: String {
        lock.lock()
        defer { lock.unlock() }
        return frontmostName.isEmpty ? frontmostBundleID : frontmostName
    }

    private func update(with app: NSRunningApplication?) {
        let bundleID = app?.bundleIdentifier?.lowercased() ?? ""
        let name = app?.localizedName?.lowercased() ?? ""
        lock.lock()
        frontmostBundleID = bundleID
        frontmostName = name
        lock.unlock()
    }
}
