/// Input decoded by `HotKeyManager`, delivered to `SwitcherController` on the
/// main thread.
enum SwitcherCommand {
    /// Start a session. `sameApp` limits it to the frontmost app's windows (⌥+`);
    /// `reverse` starts on the last window (⌥⇧+Tab).
    case open(sameApp: Bool, reverse: Bool)
    case next
    case previous
    case move(Direction)
    case commit
    case cancel
    case action(WindowAction)

    enum Direction {
        case left, right, up, down
    }
}

/// Operations on the highlighted window while the switcher is open.
enum WindowAction {
    case close      // W
    case minimize   // M (toggles)
    case hide       // H (toggles the whole app)
    case quit       // Q (the whole app)
}
