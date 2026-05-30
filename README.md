# AltTabClone

A native macOS app, written in Swift, that brings **Windows-style Alt+Tab** to the
Mac: a single switcher that cycles through **individual windows** of every app
(not just apps, the way macOS's built-in ⌘+Tab does), with live thumbnail
previews, most-recently-used ordering, and quick flip-back.

## Behavior

| Action                             | Result                                              |
| ---------------------------------- | --------------------------------------------------- |
| **⌥ Tab** (hold ⌥, tap Tab)        | Open the switcher and highlight the previous window |
| **⌥ Tab Tab …** (keep tapping Tab) | Move the highlight forward through windows          |
| **⌥ ⇧ Tab**                        | Move the highlight backward                         |
| **Release ⌥**                      | Switch to the highlighted window                    |
| **Quick ⌥+Tab tap**                | Instantly flip to the most-recent window            |
| **Esc** (while open)               | Cancel without switching                            |
| **Click a thumbnail**              | Switch to that window                               |

On a Mac keyboard the **⌥ Option key is the Alt key**, so the chord is
physically identical to Windows' Alt+Tab.

Windows are listed **most-recently-used first**, so the second item is always the
window you were just on — letting a quick tap flip between two windows exactly
like Windows.

## Build & run

```bash
./build-app.sh          # builds AltTabClone.app (release, ad-hoc signed)
open AltTabClone.app
```

For a plain debug build during development:

```bash
swift build
.build/debug/AltTabClone
```

## Permissions

On first launch macOS will ask for two permissions:

1. **Accessibility** — _required._ Used to enumerate windows, read titles, and
   raise the chosen window. Grant it in
   **System Settings → Privacy & Security → Accessibility**, then **relaunch**.
2. **Screen Recording** — _optional._ Used only to render live window
   thumbnails. If you decline, the switcher still works and falls back to large
   app icons.

The app is ad-hoc code-signed with a stable bundle identifier
(`com.alttabclone.app`) so these permissions persist across rebuilds.

## How it works

- **`WindowEnumerator`** — pulls the on-screen window list from
  `CGWindowListCopyWindowInfo` (which gives front-to-back z-order), correlates
  each entry with its `AXUIElement` via the `_AXUIElementGetWindow` SPI, and
  maintains a most-recently-used ordering.
- **`HotKeyManager`** — a `CGEventTap` that intercepts the ⌥+Tab chord globally,
  swallowing Tab so the focused app never sees it, and commits on ⌥ release.
- **`ThumbnailProvider`** — captures window previews asynchronously with
  ScreenCaptureKit (`SCScreenshotManager`).
- **`SwitcherController` + `SwitcherView`** — a borderless, non-activating
  `NSPanel` hosting a SwiftUI overlay; non-activating so switching focus to the
  target window is clean.
- **`WindowActivator`** — raises the selected window (`kAXRaiseAction`) and
  activates its owning application.

## Run it at login

Since it's an `LSUIElement` agent (no Dock icon), add `AltTabClone.app` to
**System Settings → General → Login Items** to have it always available.

## Notes / limitations

- Shows on-screen windows. Minimized windows are un-minimized when selected but
  aren't listed while hidden (a future enhancement).
- Uses **⌥+Tab** rather than overriding the system's **⌘+Tab**, so it coexists
  with macOS's built-in app switcher instead of fighting it.
