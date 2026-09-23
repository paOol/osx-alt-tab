import os

/// Diagnostics, viewable with:
///     log stream --level debug --predicate 'subsystem == "com.alttabclone.app"'
enum Log {
    static let app = Logger(subsystem: "com.alttabclone.app", category: "app")
    static let switcher = Logger(subsystem: "com.alttabclone.app", category: "switcher")
}
