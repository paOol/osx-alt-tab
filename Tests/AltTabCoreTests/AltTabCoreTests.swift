import CoreGraphics
import Testing
@testable import AltTabCore

@Suite struct MRUListTests {
    @Test func touchMovesToFront() {
        var mru = MRUList([1, 2, 3])
        mru.touch(3)
        #expect(mru.order == [3, 1, 2])
    }

    @Test func touchInsertsUnknownId() {
        var mru = MRUList([1, 2])
        mru.touch(9)
        #expect(mru.order == [9, 1, 2])
    }

    @Test func reconcileDropsClosedAndAppendsNewInZOrder() {
        var mru = MRUList([3, 1, 2])
        mru.reconcile(present: [5, 1, 4, 3])
        #expect(mru.order == [3, 1, 5, 4])
    }

    @Test func reconcileIgnoresDuplicates() {
        var mru = MRUList<Int>()
        mru.reconcile(present: [1, 2, 1])
        #expect(mru.order == [1, 2])
    }

    /// Focus changes made outside the switcher (⌘+Tab, clicks) must drive the
    /// quick-flip target, not just switches made through it.
    @Test func externalFocusChangeUpdatesFlipTarget() {
        var mru = MRUList<Int>()
        mru.reconcile(present: [1, 2, 3])
        mru.touch(3) // user ⌘+Tabs to window 3
        #expect(mru.order[1] == 1)
    }
}

@Suite struct SelectionTests {
    @Test func initialSelection() {
        #expect(Selection.initial(count: 0) == 0)
        #expect(Selection.initial(count: 1) == 0)
        #expect(Selection.initial(count: 4) == 1)
        #expect(Selection.initial(count: 4, reverse: true) == 3)
    }

    @Test func stepWraps() {
        #expect(Selection.step(3, by: 1, count: 4) == 0)
        #expect(Selection.step(0, by: -1, count: 4) == 3)
        #expect(Selection.step(0, by: 1, count: 0) == 0)
    }

    @Test func moveRowStaysInBounds() {
        // 7 items in rows of 3: [0 1 2] [3 4 5] [6]
        #expect(Selection.moveRow(1, by: 1, columns: 3, count: 7) == 4)
        #expect(Selection.moveRow(4, by: 1, columns: 3, count: 7) == 4)
        #expect(Selection.moveRow(3, by: 1, columns: 3, count: 7) == 6)
        #expect(Selection.moveRow(1, by: -1, columns: 3, count: 7) == 1)
    }
}

@Suite struct AppMatcherTests {
    @Test func matchesBundleIDOrNameCaseInsensitively() {
        let matcher = AppMatcher(patterns: ["Moonlight", "com.microsoft.rdc", ""])
        #expect(matcher.matches(bundleID: "com.moonlight-stream.Moonlight", name: nil))
        #expect(matcher.matches(bundleID: "com.microsoft.rdc.macos", name: "Windows App"))
        #expect(matcher.matches(bundleID: nil, name: "MOONLIGHT"))
        #expect(!matcher.matches(bundleID: "com.apple.Safari", name: "Safari"))
        #expect(!matcher.matches(bundleID: nil, name: nil))
    }

    @Test func emptyPatternsMatchNothing() {
        let matcher = AppMatcher(patterns: ["", ""])
        #expect(matcher.isEmpty)
        #expect(!matcher.matches(bundleID: "anything", name: "anything"))
    }
}

@Suite struct WindowFilterTests {
    let onMain = CGRect(x: 100, y: 100, width: 800, height: 600)

    @Test func defaultsIncludeEverything() {
        let filter = WindowFilter()
        #expect(filter.includes(WindowTraits(bundleID: "a", appName: "A", bounds: onMain, isMinimized: true)))
        #expect(filter.includes(WindowTraits(bundleID: "a", appName: "A", bounds: onMain, isAppHidden: true)))
        #expect(filter.includes(WindowTraits(bundleID: "a", appName: "A", bounds: onMain, isOnOtherSpace: true)))
    }

    @Test func toggles() {
        var filter = WindowFilter()
        filter.showMinimized = false
        filter.showHidden = false
        filter.showOtherSpaces = false
        #expect(!filter.includes(WindowTraits(bundleID: "a", appName: "A", bounds: onMain, isMinimized: true)))
        #expect(!filter.includes(WindowTraits(bundleID: "a", appName: "A", bounds: onMain, isAppHidden: true)))
        #expect(!filter.includes(WindowTraits(bundleID: "a", appName: "A", bounds: onMain, isOnOtherSpace: true)))
        #expect(filter.includes(WindowTraits(bundleID: "a", appName: "A", bounds: onMain)))
    }

    @Test func excludedApps() {
        var filter = WindowFilter()
        filter.excluded = AppMatcher(patterns: ["finder"])
        #expect(!filter.includes(WindowTraits(bundleID: "com.apple.finder", appName: "Finder", bounds: onMain)))
        #expect(filter.includes(WindowTraits(bundleID: "com.apple.Safari", appName: "Safari", bounds: onMain)))
    }

    @Test func currentScreenUsesWindowCenter() {
        var filter = WindowFilter()
        filter.screenBounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(filter.includes(WindowTraits(bundleID: nil, appName: "A", bounds: onMain)))
        // Mostly on the second display to the right.
        let straddling = CGRect(x: 1300, y: 100, width: 800, height: 600)
        #expect(!filter.includes(WindowTraits(bundleID: nil, appName: "A", bounds: straddling)))
    }
}
