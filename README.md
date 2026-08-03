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
| **⌃ ⌥ Tab**                        | Force the local switcher, even in a remote session  |

On a Mac keyboard the **⌥ Option key is the Alt key**, so the chord is
physically identical to Windows' Alt+Tab.

Windows are listed **most-recently-used first**, so the second item is always the
window you were just on — letting a quick tap flip between two windows exactly
like Windows.

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

Settings are read at launch, so restart the app after changing them
(`launchctl kickstart -k gui/$UID/com.alttabclone.app` if you installed the
LaunchAgent).

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

## Permissions

On first launch macOS will ask for two permissions:

1. **Accessibility** — _required._ Used to enumerate windows, read titles, and
   raise the chosen window. Grant it in
   **System Settings → Privacy & Security → Accessibility**, then **relaunch**.
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

- **`WindowEnumerator`** — pulls the on-screen window list from
  `CGWindowListCopyWindowInfo` (which gives front-to-back z-order), correlates
  each entry with its `AXUIElement` via the `_AXUIElementGetWindow` SPI, and
  maintains a most-recently-used ordering.
- **`HotKeyManager`** — a `CGEventTap` that intercepts the ⌥+Tab chord globally,
  swallowing Tab so the focused app never sees it, and commits on ⌥ release.
- **`PassthroughPolicy`** — caches the frontmost app (via
  `NSWorkspace.didActivateApplicationNotification`, so the input hot path stays
  lock-and-compare only) and tells the tap when to forward ⌥+Tab to a remote
  session or VM instead of handling it.
- **`ThumbnailProvider`** — captures window previews asynchronously with
  ScreenCaptureKit (`SCScreenshotManager`).
- **`SwitcherController` + `SwitcherView`** — a borderless, non-activating
  `NSPanel` hosting a SwiftUI overlay; non-activating so switching focus to the
  target window is clean.
- **`WindowActivator`** — raises the selected window (`kAXRaiseAction`) and
  activates its owning application.

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

- Shows on-screen windows. Minimized windows are un-minimized when selected but
  aren't listed while hidden (a future enhancement).
- Uses **⌥+Tab** rather than overriding the system's **⌘+Tab**, so it coexists
  with macOS's built-in app switcher instead of fighting it.
