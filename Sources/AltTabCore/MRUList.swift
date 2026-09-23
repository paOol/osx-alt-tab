/// Most-recently-used ordering of window ids, newest first.
///
/// `touch` is called whenever a window gains focus (by any means — this app,
/// ⌘+Tab, a click, the Dock), so index 1 is always the window you were just on.
public struct MRUList<ID: Hashable> {
    public private(set) var order: [ID] = []

    public init(_ order: [ID] = []) {
        self.order = order
    }

    /// Record that `id` was just focused, moving it to the front.
    public mutating func touch(_ id: ID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    /// Drop ids that no longer exist and append newly seen ones in the order
    /// given (front-to-back z-order), so unseen windows sort after known ones.
    public mutating func reconcile(present: [ID]) {
        let presentSet = Set(present)
        order.removeAll { !presentSet.contains($0) }
        var known = Set(order)
        for id in present where known.insert(id).inserted {
            order.append(id)
        }
    }
}
