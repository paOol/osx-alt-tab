/// Matches apps against user-supplied patterns. Each pattern is compared
/// case-insensitively as a substring of the bundle identifier *or* the app
/// name, so a bare "moonlight" is enough.
public struct AppMatcher {
    public let needles: [String]

    public init(patterns: [String]) {
        needles = patterns.map { $0.lowercased() }.filter { !$0.isEmpty }
    }

    public var isEmpty: Bool { needles.isEmpty }

    public func matches(bundleID: String?, name: String?) -> Bool {
        let bundleID = bundleID?.lowercased() ?? ""
        let name = name?.lowercased() ?? ""
        guard !bundleID.isEmpty || !name.isEmpty else { return false }
        return needles.contains { bundleID.contains($0) || name.contains($0) }
    }
}
