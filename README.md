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
| **⌥ ⇧ Tab**                        | Open on the last window / move backward             |
| **⌥ \`**                           | Same, but only the frontmost app's windows          |
| **Release ⌥**                      | Switch to the highlighted window                    |
| **Quick ⌥+Tab tap**                | Instantly flip to the most-recent window            |
| **← → ↑ ↓** (while open)           | Move the highlight around the grid                  |
| **Return** (while open)            | Switch to the highlighted window                    |
| **W** (while open)                 | Close the highlighted window                        |
| **M** (while open)                 | Minimize / restore the highlighted window           |
| **H** (while open)                 | Hide / unhide the highlighted window's app          |
| **Q** (while open)                 | Quit the highlighted window's app                   |
| **Esc** (while open)               | Cancel without switching                            |
| **Hover / click a thumbnail**      | Highlight / switch to that window                   |
| **⌃ ⌥ Tab**                        | Force the local switcher, even in a remote session  |

While the switcher is open, every key goes to the switcher — nothing leaks
through to the app underneath. W/M/H/Q follow your keyboard layout.

On a Mac keyboard the **⌥ Option key is the Alt key**, so the chord is
physically identical to Windows' Alt+Tab.

Windows are listed **most-recently-used first**, so the second item is always the
window you were just on — letting a quick tap flip between two windows exactly
like Windows. Focus changes made any other way (⌘+Tab, clicking, the Dock,
Mission Control) count too.

Minimized windows, windows of hidden (⌘H) apps, and windows on other Spaces —
including fullscreen apps — are listed with a small badge. Selecting one
restores it and switches to it.

The overlay waits ~120 ms before appearing, so a quick flip switches without
flashing the panel. Pressing Tab again shows it immediately.

## Settings

All settings are optional `defaults` keys, applied from the next ⌥+Tab — no
relaunch needed:

| Key                     | Type         | Default | Effect                                              |
| ----------------------- | ------------ | ------- | --------------------------------------------------- |
| `ShowMinimizedWindows`  | bool         | `true`  | List minimized windows                              |
| `ShowHiddenApps`        | bool         | `true`  | List windows of apps hidden with ⌘H                 |
| `ShowOtherSpaces`       | bool         | `true`  | List windows on other Spaces / fullscreen apps      |
| `CurrentScreenOnly`     | bool         | `false` | Only list windows on the screen under the mouse     |
| `ExcludedApps`          | string array | empty   | Never list these apps (bundle ID or name substring) |
| `ShowDelayMilliseconds` | number       | `120`   | Delay before the overlay appears (`0` = immediate)  |
| `ThumbnailWidth`        | number       | `200`   | Thumbnail width in points (80–600)                  |
| `SameAppShortcut`       | bool         | `true`  | Enable ⌥+\` (turn off if you type accents with it)  |
| `PassthroughEnabled`    | bool         | `true`  | See [Remote sessions and VMs](#remote-sessions-and-vms-moonlight-parsec-rdp-parallels-) |
| `PassthroughApps`       | string array | built-in list | 〃                                             |

```bash
defaults write com.alttabclone.app ExcludedApps -array finder "system settings"
defaults write com.alttabclone.app ShowOtherSpaces -bool false
defaults write com.alttabclone.app ShowDelayMilliseconds -int 0
defaults delete com.alttabclone.app ThumbnailWidth   # back to default
```

## Remote sessions and VMs (Moonlight, Parsec, RDP, Parallels …)

When one of these clients is frontmost it's running a whole other OS inside its
window, and Alt+Tab belongs to that **guest** session — so the switcher steps
aside and forwards the chord untouched. Alt+Tab inside a streamed Windows
desktop switches Windows' windows, natively. The moment you leave that app or
quit it, the macOS switcher takes over again. There's no mode to toggle.

If a fullscreen client ever traps you, **⌃⌥+Tab** always opens the local
switcher.

Recognized out of the box: Moonlight, Parsec, Microsoft Remote Desktop,
TeamViewer, AnyDesk, Chrome Remote Desktop, VMware, Parallels, VirtualBox, UTM,
Steam Remote Play, and VNC clients.

Customize it — entries match case-insensitively against the app's bundle ID or
its name, so a bare word is enough:

```bash
# replace the list
defaults write com.alttabclone.app PassthroughApps -array moonlight parsec "citrix"

# back to the built-in list
defaults delete com.alttabclone.app PassthroughApps

# disable pass-through entirely (⌥+Tab is always the macOS switcher)
defaults write com.alttabclone.app PassthroughEnabled -bool false
```

Changes apply from the next ⌥+Tab.

## Build & run

```bash
./install.sh            # build + install to ~/Applications, run at login
```

That is the normal path, and it deliberately produces **exactly one** copy of
the app. `./build-app.sh` on its own only stages an ad-hoc-signed bundle at
`.build/AltTabClone.app`; keeping a second bundle at a launchable path means two
entries in the Accessibility list and two things fighting over ⌥+Tab, so don't
copy it elsewhere — let `install.sh` place it.

For a plain debug build during development (quit the installed copy first, or
both will grab the hotkey):

```bash
swift build
.build/debug/AltTabClone
```

Unit tests cover the pure logic in `AltTabCore` (MRU ordering, selection,
filtering, app matching):

```bash
swift test
```

## Permissions

On first launch macOS will ask for two permissions:

1. **Accessibility** — _required._ Used to enumerate windows, read titles, and
   raise the chosen window. Grant it in
   **System Settings → Privacy & Security → Accessibility**; the app notices
   within a second and starts on its own.
2. **Screen Recording** — _optional._ Used only to render live window
   thumbnails. If you decline, the switcher still works and falls back to large
   app icons.

### Why permissions must be signed to stick

macOS attaches a permission grant to the app's **designated requirement** — a
rule it stores when you grant access and re-evaluates on every launch.

An ad-hoc signature gets a default requirement that is nothing but the binary's
own hash:

```
cdhash H"<binary hash>"
```

Relinking changes that hash, so every rebuild silently invalidates the grant.
The failure mode is easy to misread: the app still appears **checked**
in System Settings but is not actually trusted, and un-checking and re-checking
it does _not_ help, because System Settings rewrites the row from the stale
requirement it already stored.

`build-app.sh` avoids this by passing the requirement to `codesign` explicitly
(`-r=`), pinning it to the bundle identifier instead of the hash:

```
designated => identifier "com.alttabclone.app"
```

That survives rebuilds, so you grant Accessibility once and it holds — with no
certificate, no keychain and no setup step. The build fails loudly if the
requirement ever comes out hash-based again.

The tradeoff is that a requirement this loose is satisfied by any ad-hoc binary
claiming this bundle identifier, so the grant isn't bound to this build in
particular. That's a reasonable trade for a locally-built personal tool; an app
distributed to other people should sign with a real Developer ID certificate,
which is both stable _and_ bound to the signer.

If you land in that state, remove the entry with the **–** button in
**System Settings → Privacy & Security → Accessibility**, or run:

```bash
tccutil reset Accessibility com.alttabclone.app
```

then relaunch and grant it again. `install.sh` does this automatically whenever
it detects that the signing identity changed.

## How it works

- **`WindowEnumerator`** — pulls every window from `CGWindowListCopyWindowInfo`
  (on-screen ones first, in front-to-back z-order), correlates each entry with
  its `AXUIElement` via the `_AXUIElementGetWindow` SPI, keeps only real
  top-level windows (standard/dialog subrole), and applies the filters.
- **`OtherSpaceWindowFinder`** — the public AX API only reports windows on the
  current Space, so windows on other Spaces are found in the background via the
  `_AXUIElementCreateWithRemoteToken` SPI and cached (refreshed on Space
  changes).
- **`FocusTracker`** — maintains the most-recently-used order from app
  activations and per-app `AXObserver` focused-window notifications.
- **`HotKeyManager`** — a `CGEventTap` on its own thread (so a busy main
  thread never adds typing latency) that intercepts ⌥+Tab globally, swallows
  every key while the switcher is open, and commits on ⌥ release. A watchdog
  in the controller finishes the session if a release is ever missed.
- **`AltTabCore`** — AppKit-free logic (MRU list, selection math, filters),
  unit tested.
- Every Accessibility call is capped at 250 ms, so a hung app can't freeze the
  switcher.
- **`PassthroughPolicy`** — caches the frontmost app (via
  `NSWorkspace.didActivateApplicationNotification`, so the input hot path stays
  lock-and-compare only) and tells the tap when to forward ⌥+Tab to a remote
  session or VM instead of handling it.
- **`ThumbnailProvider`** — captures window previews in parallel with
  ScreenCaptureKit (`SCScreenshotManager`), sized to what's displayed. The last
  preview of each window is cached and shown instantly on the next open.
- **`SwitcherController` + `SwitcherView`** — a borderless, non-activating
  `NSPanel` hosting a SwiftUI overlay; non-activating so switching focus to the
  target window is clean.
- **`WindowActivator`** — makes the owning app frontmost through
  Accessibility (not subject to macOS 14's cooperative activation), then raises
  the selected window, un-hiding or un-minimizing it first.

## Run it at login

**Recommended — installer (LaunchAgent):**

```bash
./install.sh
```

This builds the app, copies it to `~/Applications/AltTabClone.app` (a stable
home so permissions stick), and installs a `launchd` agent at
`~/Library/LaunchAgents/com.alttabclone.app.plist` with `RunAtLoad` +
`KeepAlive` — so it starts at every login and relaunches if it ever crashes.
It starts running immediately too.

After the first install, grant **Accessibility** access to
`~/Applications/AltTabClone.app`, then restart it:

```bash
launchctl kickstart -k "gui/$(id -u)/com.alttabclone.app"
```

To remove it completely:

```bash
./uninstall.sh
```

**Alternative — Login Items:** since it's an `LSUIElement` agent (no Dock icon),
you can instead just add `AltTabClone.app` to
**System Settings → General → Login Items**. (This starts it at login but won't
auto-restart it if it crashes — the LaunchAgent does.)

## Notes / limitations

- A window on another Space that has never been seen may take one extra ⌥+Tab
  to appear: it's discovered in the background the first time it's missed.
- Minimized windows show their last cached preview (or the app icon), since
  macOS can't capture them while minimized.
- Uses **⌥+Tab** rather than overriding the system's **⌘+Tab**, so it coexists
  with macOS's built-in app switcher instead of fighting it.
