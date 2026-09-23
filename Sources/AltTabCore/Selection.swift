/// Index arithmetic for the switcher's selection, laid out as a grid of
/// `columns` items per row.
public enum Selection {
    /// Where a new session starts: the previous window, so a quick tap flips
    /// back (matching Windows), or the last one when opened in reverse.
    public static func initial(count: Int, reverse: Bool = false) -> Int {
        guard count > 1 else { return 0 }
        return reverse ? count - 1 : 1
    }

    /// Step forward/backward through the list, wrapping at both ends.
    public static func step(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + delta) % count + count) % count
    }

    /// Move one row up (`rows < 0`) or down in the grid. Stays put when there
    /// is no item directly above/below, rather than jumping somewhere surprising.
    public static func moveRow(_ index: Int, by rows: Int, columns: Int, count: Int) -> Int {
        guard columns > 0 else { return index }
        let target = index + rows * columns
        return (0..<count).contains(target) ? target : index
    }
}
