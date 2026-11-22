# Dock+ — v1 Specification (multi-dock app)

- **Status:** v1 design, ready to build from
- **Date:** 2026-11-20
- **Owner:** flaxogic
- **Project folder (Mac Mini):** `/Users/alex/Desktop/Flaxogic/Projects/Dock+`
- **Name:** **Dock+** (decided by flaxogic 2026-11-20)
- **Bundle ID:** `com.flaxogic.dockplus` (`+` is not allowed in a bundle ID, so the ID uses `dockplus`; the product name is Dock+)
- **Repo name:** `dock-plus` (GitHub, public, MIT — check availability before creating, §16)

---

## 1. Overview

A native macOS app that lets you create **multiple custom docks** — each one a
small floating launcher with its own apps, files, and folders — and place them
anywhere on any screen.

It is the simple, free core of what ExtraDock does, without the paid licence
and without the widget/theme bloat:

- ExtraDock is closed-source and paid (~$9.99/yr, or a lifetime licence).
- The existing free/open-source dock tools do something else: MultiScreenDock
  only *mirrors* the one system Dock onto every monitor (same items
  everywhere), and Docky is a single Dock *replacement*. Neither gives you
  different, custom docks for different jobs.
- This app fills that gap: **a Coding dock, a Comms dock, a Design dock —
  each where you want it, on the screen you want it on.**

The product promise, verbatim: **"Multiple docks for Mac. Free forever,
open source, no account, no telemetry, nothing leaves your Mac."**

Two constraints drive the whole design and are accepted, not worked around:

1. **Free & open source, forever.** No paid tier, no trial, no feature
   paywall, no account. MIT licence (§2 D3). If a feature is in the app,
   it is free for everyone.
2. **Simple.** v1 is a launcher, not a platform. No widgets, no themes,
   no pets, no window previews. Every v1 feature must pass: "does this
   help someone launch the right app from the right screen faster?"

### 1.1 Goals (v1)

- Create any number of independent docks, each with its own items.
- Items are **apps, files, and folders**, added by drag & drop, launched /
  opened with one click.
- Each dock can be horizontal or vertical, free-floating or snapped to a
  screen edge, and pinned to a specific display (or shown on any display).
- Docks survive relaunch exactly as left: items, order, position, display,
  size, and behaviour.
- Running apps in a dock show a running indicator.
- Basic per-dock styling: icon size, spacing, background opacity/blur.
- Basic per-dock behaviour: always visible, auto-hide at a screen edge,
  and hide during fullscreen apps.
- Menu-bar app: no Dock icon of its own, launch at login, near-zero idle
  CPU/memory. "Zero lag with multiple docks" is a requirement, not a hope.

### 1.2 Non-goals (v1)

- **Replacing or removing the system Dock.** macOS protects it; this app
  runs *alongside* it. The app may *advise* the user to set the system
  Dock to auto-hide, but never modifies system Dock settings itself.
- Widgets of any kind (clock, spacer is the one exception — see §6.4 —
  trash, battery, CPU, pets). Deferred to v2 (§15).
- Live Dock mirroring of the system Dock. Deferred to v2 (§15). A one-time
  *import* of the system Dock's pinned apps at first run is v1 (§11).
- Magnification, themes/colour schemes, custom app icons, Liquid Glass
  effects. Deferred to v2 (§15).
- Folder stacks/popups, window previews, per-window switching. Folder
  items simply open in Finder in v1.
- Notification badges. macOS does not expose badges (notably Mail and
  Messages) to third-party launchers; v1 shows none rather than faking
  some (§13).
- Spaces-aware docks (different items per Space), dock profiles/presets,
  and preset switching à la DockFlow. Deferred to v2 (§15).
- Mac App Store distribution (§12), Windows/Linux versions, iOS anything.

---

## 2. Decisions log

Every row is a decision already made. Do not re-litigate while building v1;
raise changes against this table explicitly.

| # | Decision | Choice |
|---|----------|--------|
| D1 | Platform | **Mac only** for v1 |
| D2 | Toolchain | Native app in **Xcode**, Swift. **AppKit** for dock windows (`NSPanel`) and drag & drop; **SwiftUI** for Settings and menu UI |
| D3 | Licence & price | **MIT, free & open source**, public GitHub repo from the first commit. No paid tier, ever |
| D4 | System Dock | App runs **alongside** it, never replaces/removes/hides it programmatically |
| D5 | Permissions | **None required for v1 core.** No Accessibility, no Screen Recording, no Full Disk Access. If the app ever asks for a permission in v1, that is a bug |
| D6 | Data & privacy | All state is **local only**: one JSON config file (§4.2). No analytics, no telemetry, no network calls at all in v1 — the app should work fully offline and never phone home, including no update checks (updates are manual via GitHub/Homebrew) |
| D7 | Minimum macOS | **macOS 14 (Sonoma)**. Universal binary (Apple Silicon + Intel) |
| D8 | App shape | **Menu-bar agent** (`LSUIElement = true`): menu-bar icon + Settings window, no Dock icon, no main window |
| D9 | Dock independence | Every dock is fully independent: items, orientation, position, display pin, style, and behaviour are per-dock, never global (except §10.3 global toggles) |
| D10 | Item types (v1) | **App, file, folder** — plus one layout item: a thin **separator** (§6.4). No other item types in v1 |
| D11 | Live Dock | **Not in v1.** One-time import from the system Dock at first run only (§11) |
| D12 | Distribution | **GitHub Releases + Homebrew cask**, not the Mac App Store (§12). No sandbox in v1, which keeps file/folder launching simple and honest |
| D13 | Name | **Dock+** (decided by flaxogic 2026-11-20). Bundle ID `com.flaxogic.dockplus` (`+` cannot appear in a bundle ID); Xcode project/target named `DockPlus` for the same reason; the user-facing product name is Dock+ everywhere |

Defaults flagged for veto (chosen by Muse, not yet user-confirmed — they do
not block building): icon size default 48 pt; new docks start horizontal,
bottom-centre of the main display; auto-hide and fullscreen-hide default
**off** for a user's first dock, so the first-run experience is "it stays
where I put it".

---

## 3. Architecture

```
┌────────────────────────────────────────────────────────────┐
│ Menu-bar agent (AppKit app, SwiftUI Settings + menus)      │
├────────────────────────────────────────────────────────────┤
│ DockManager          SettingsViewModel      MenuController │
│  owns [DockID: DockPanelController], display observer      │
├────────────────────────────────────────────────────────────┤
│ DockPanelController (one per dock)                         │
│   ├─ NSPanel (floating, non-activating, all-Spaces)        │
│   ├─ DockItemStripView (icons, drag & drop, reordering)    │
│   └─ AutoHideController / FullscreenWatcher (per dock)     │
├──────────────────┬──────────────────┬──────────────────────┤
│ ConfigStore (§4) │ Launcher         │ RunningAppObserver   │
│ JSON file,       │ NSWorkspace      │ NSWorkspace          │
│ debounced save,  │ open / activate  │ notifications,       │
│ schema version   │                  │ running dots         │
├──────────────────┴──────────────────┴──────────────────────┤
│ macOS: AppKit, NSWorkspace, NSVisualEffectView, SMAppService│
└────────────────────────────────────────────────────────────┘
```

### 3.1 Components

- **DockManager** — single source of truth for the dock list. Creates,
  deletes, and reconfigures `DockPanelController`s; observes display
  connect/disconnect and Space/fullscreen changes and tells controllers
  to show/hide.
- **DockPanelController** — owns one dock's `NSPanel` and its content.
  Applies that dock's config (position, orientation, style, behaviour)
  and nothing else's. Controllers never talk to each other.
- **DockItemStripView** — renders the item row/column, handles click,
  hover tooltip, context menu, and all drag & drop (§6, §7).
- **ConfigStore** — loads/saves the JSON config (§4.2), migrates schema
  versions, writes atomically, and keeps one `.bak` of the last good file.
  A corrupt config must never crash the app: fall back to the backup,
  then to a single empty starter dock.
- **Launcher** — wraps `NSWorkspace`: open an app (or activate it if
  already running — a plain click activates/shows, it never launches a
  second copy), open a file with its default app, open a folder in Finder.
- **RunningAppObserver** — observes `NSWorkspace` launch/terminate
  notifications once, centrally, and publishes the running bundle-ID set
  to all controllers for their running dots (§6.3).
- **Settings UI (SwiftUI)** — dock list + per-dock editor (§10). Editing
  in Settings and dragging on the dock itself write through the same
  `DockManager` API, so the two can never disagree.

### 3.2 Suggested Xcode project layout

```
DockPlus/
  App/            AppDelegate, MenuController, main
  Docks/          DockManager, DockPanelController, AutoHideController
  Views/          DockItemStripView, DockItemView, Settings/*
  Model/          DockConfig, DockItem, ConfigStore
  Services/       Launcher, RunningAppObserver, DisplayObserver,
                  DockImporter (first-run system-Dock import, §11)
  Resources/      Assets, Info.plist (LSUIElement), entitlements (none)
DockPlusTests/   ConfigStore round-trip + migration, DockImporter parsing,
                  geometry (snap / clamp) unit tests
```

No third-party dependencies in v1. If a dependency ever seems necessary,
that is a design smell — raise it against D2/D6 first.

---

## 4. Data model & persistence

### 4.1 Model

```swift
struct DockConfig: Codable, Identifiable {
    var id: UUID
    var name: String                 // e.g. "Coding" — shown in menus/Settings
    var items: [DockItem]
    var orientation: Orientation     // .horizontal | .vertical
    var placement: Placement         // see below
    var iconSize: Double             // 32...80 pt, default 48
    var itemSpacing: Double          // 0...16 pt, default 6
    var backgroundOpacity: Double    // 0...1, default system blur at 1.0
    var autoHide: Bool               // only meaningful when snapped (§8.1)
    var hideInFullscreen: Bool
    var isLocked: Bool               // position locked against dragging
    var isVisible: Bool              // user toggled this dock off/on
}

enum Placement: Codable {
    case floating(x: Double, y: Double, displayUUID: String?)
    case snapped(edge: Edge, offset: Double, displayUUID: String?)
    // Edge: .bottom | .top | .left | .right
    // offset = distance along the edge from its centre, in points
}

struct DockItem: Codable, Identifiable {
    var id: UUID
    var kind: Kind                   // .app | .file | .folder | .separator
    var path: String?                // nil for .separator
    var labelOverride: String?       // v1: parsed/stored, editing UI is v2
}
```

- Display identity is the display's persistent UUID
  (`CGDisplayCreateUUIDFromDisplayID` / `NSScreen` device description),
  never its numeric ID or its position in the screens array — both change
  across reconnects and reboots.
- Positions are stored per placement, in global screen coordinates for
  floating docks. On show, a position is **clamped** into the target
  display's visible frame; a dock is never restored off-screen (§8.3).
- Items store plain filesystem paths (D12: no sandbox, so no
  security-scoped bookmarks are needed in v1). A missing path at render
  time (app uninstalled, volume unmounted) renders as a dimmed `?` tile
  with a "not found" tooltip — never a crash, never silent removal.
  The user removes dead items explicitly (§7.3).

### 4.2 Persistence

- One file: `~/Library/Application Support/DockPlus/config.json`,
  `schemaVersion` at top level, currently `1`.
- Save is debounced (300 ms) after any change and always atomic
  (write-temp-then-rename). Keep `config.json.bak` (previous good save).
- No per-item files, no database, no `UserDefaults` for dock data.
  `UserDefaults` is only for trivial UI state (e.g. last Settings tab).

---

## 5. Dock windows

- One `NSPanel` per dock: `.nonactivatingPanel`, borderless, floating
  window level (`.floating`), `hidesOnDeactivate = false`,
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
  .stationary]` so docks stay put across Spaces and can sit over
  fullscreen apps when their config says to.
- Background is `NSVisualEffectView` (`.hudWindow` / popover material)
  with the dock's opacity applied; rounded corners (12 pt), subtle
  border, subtle shadow. No custom colours in v1 (v2 themes).
- Clicking a dock item must never steal focus from the user's current
  app beyond what launching/activating the target itself does — the
  panel is non-activating for exactly this reason.
- **Moving a dock:** drag by any empty strip area or the dock's end
  handle. Dragging near a screen edge (within 16 pt) snaps to that edge
  and flips orientation to match (bottom/top → horizontal, left/right →
  vertical); dragging away from the edge un-snaps to floating. A locked
  dock (`isLocked`) does not move and shows why in its tooltip/menu.
- Resizing is implicit: the panel sizes to its items × icon size +
  spacing + padding. There is no manual width/height handle in v1.

---

## 6. Items & launching

### 6.1 Rendering

- Each item is its real Finder icon (`NSWorkspace.icon(forFile:)`),
  at the dock's icon size, with the item's name as tooltip.
- Hover: slight scale (1.08×) + name tooltip. No magnification in v1.
- A separator is a thin line (vertical in a horizontal dock, and vice
  versa), non-clickable, draggable for reordering like any item.

### 6.2 Click behaviour

| Item | Click | ⌥-click / right-click menu |
|------|-------|----------------------------|
| App, not running | Launch it | Open, Show in Finder, Remove from Dock |
| App, running | Activate / bring to front | Open (new instance is **not** offered in v1), Hide, Quit, Show in Finder, Remove from Dock |
| File | Open with default app | Open With… is **not** in v1; Show in Finder, Remove |
| Folder | Open in Finder | Show in Finder (parent), Remove |
| Separator | — | Remove |

- Right-click on empty strip area: dock menu — Add Items…, Hide This
  Dock, Lock/Unlock Position, Dock Settings…, (and in the menu-bar menu:
  New Dock, Show/Hide All Docks).

### 6.3 Running indicator

- A 4 pt dot under (horizontal) / beside (vertical) the icon when the
  app is running, from `RunningAppObserver`'s bundle-ID set. Files and
  folders never show a dot. Updates arrive via `NSWorkspace`
  notifications only — **no polling**.

### 6.4 Separators

- Added from the dock menu ("Add Separator") or Settings. This is the
  one non-launcher item in v1 because grouping inside a dock is core
  to the "different dock per job" use, and it costs almost nothing.

---

## 7. Adding, reordering, removing

### 7.1 Adding

Three ways, all equivalent in result:

1. **Drag & drop** a file/app/folder from Finder or the Applications
   folder onto a dock — insert indicator shows the drop position.
2. **Dock menu → Add Items…** — standard open panel, multi-select,
   apps/files/folders allowed.
3. **Settings → dock → Add Items…** — same panel, for keyboard users.

- Dropping a duplicate (same path already in that dock) is a no-op with
  a brief shake/beep — duplicates across *different* docks are fine.
- Dropping a folder classifies as `.folder`; an `.app` bundle as `.app`;
  anything else as `.file`. Classification is by bundle/UTI, not extension
  string matching alone.

### 7.2 Reordering

- Drag an item along the strip; other items slide to preview the new
  order; drop commits it. Also reorderable as a list in Settings
  (keyboard-accessible path — drag-only reordering is an accessibility
  failure, not a style choice).

### 7.3 Removing

- Right-click item → Remove from Dock, or drag the item off the strip
  (past 40 pt) and release (poof is optional; a simple fade is fine),
  or delete it in the Settings list. All three are undoable via ⌘Z for
  the last removal in the same session (single-step undo is enough).

---

## 8. Placement, displays & behaviour

### 8.1 Auto-hide

- Only for **snapped** docks (a floating dock has no edge to hide at).
  The dock slides off its edge leaving a 2 pt sliver; moving the mouse
  to that edge of that display reveals it after a 150 ms dwell;
  moving away hides it after 400 ms. Timings are constants in v1,
  not settings.

### 8.2 Fullscreen hiding

- If `hideInFullscreen` is on, the dock hides while the frontmost app
  on its display is in native fullscreen, and returns when fullscreen
  exits. Detection via `NSWorkspace` active-app changes + window-list
  fullscreen check on that display — no Screen Recording permission
  (window *titles* are never read; only geometry/flags).

### 8.3 Displays

- A dock's display pin is a display UUID, or `nil` = "the display it is
  currently on" (floating docks remember their last display).
- On disconnect of a dock's display: hide the dock, keep its config.
  On reconnect of the same display UUID: show it again, clamped into
  the visible frame. This hide/restore cycle is a headline feature and
  has a dedicated acceptance test (§14, A7).
- At launch, a dock whose display is absent stays hidden (not dumped
  onto the main display) until that display appears.
- Single-display use must work perfectly — multi-display is an addition,
  not a requirement. With one display, display pinning UI is hidden.

### 8.4 Spaces

- Docks appear on **all Spaces** in v1 (`.canJoinAllSpaces`). Per-Space
  docks are v2. A dock must never cause a Space switch when clicked.

---

## 9. Global behaviour

- **Menu-bar menu:** New Dock, list of docks (click = show/hide toggle,
  ⌥-click = open that dock in Settings), Show/Hide All Docks, Settings…,
  Launch at Login (checkbox), Quit Dock+.
- **Show/Hide All** global shortcut: none assigned by default; user may
  set one in Settings (stored, conflict-checked against a small denylist
  of system shortcuts — full conflict detection is out of scope).
- **Launch at login:** via `SMAppService.mainApp`, off by default,
  offered (not forced) in the first-run flow (§11).
- **Performance budget:** idle CPU 0% in Activity Monitor sampling,
  memory ≤ 60 MB with 5 docks × 20 items, no timers polling faster
  than the auto-hide dwell logic, icons cached per (path, size) and
  invalidated on file change notifications.

---

## 10. Settings UI

One Settings window, two panes:

### 10.1 Docks pane

- Left: dock list (name, item count, display, visibility eye toggle),
  with Add / Duplicate / Delete dock (delete asks once, with item count).
- Right: selected dock editor —
  - Name (text field)
  - Items list: icon + name + path, Add Items…, Remove, drag to reorder
  - Orientation: Horizontal / Vertical (disabled note when snapped:
    orientation follows the edge)
  - Display: Any / [connected displays by name]
  - Icon size slider (32–80), spacing slider, opacity slider, live preview
    is the dock itself updating in real time — no fake preview pane
  - Behaviour checkboxes: Auto-hide (snapped only), Hide in fullscreen,
    Lock position, Visible

### 10.2 General pane

- Launch at login, Show/Hide All shortcut recorder, Reset All Docks…
  (export config first — see below), Export Config…, Import Config…
  (plain JSON file swap with schema check; this is also the backup story),
  About box: version, MIT licence link, GitHub link.

---

## 11. First run

1. First launch creates **one** starter dock, snapped bottom-centre of
   the main display, named "Dock 1".
2. It offers (once, dismissible, never nagged again) **"Copy my current
   Dock's apps"** — a one-time import (§11.1) — or starting empty.
3. A one-line hint is shown on the dock itself until the first item is
   added by drag & drop: "Drag apps here".
4. Launch-at-login is offered in the same single dialog, unchecked.

### 11.1 System-Dock import

- Read `~/Library/Preferences/com.apple.dock.plist`, `persistent-apps`
  (and `persistent-others` for folders), extract file paths, create
  items in order. Read-only: the app never writes that plist.
- Missing/unreadable plist → import option is simply not offered.
- This is a copy, not a mirror: later system-Dock changes do not sync.
  The UI wording must say exactly that, so nobody expects Live Dock.

---

## 12. Distribution & open source

- **Repo:** public GitHub from day one; `main` is always buildable;
  issues and PRs open. README leads with: what it is, screenshot/GIF,
  "Free & open source (MIT) — the ExtraDock core, without the price",
  install, build-from-source, and the honest limitations (§13).
- **Build from source:** `git clone`, open in Xcode, Run. No secrets,
  no signing identity required for local builds (ad-hoc signing).
- **Releases:** universal `.dmg` + `.zip` on GitHub Releases, semantic
  versioning, changelog per release. Homebrew cask submitted after the
  first public release (`brew install --cask dock-plus`, name to confirm).
- **Signing/notarisation — honest v1 position:** notarisation needs a
  paid Apple Developer ID ($99/yr), which a free project may not have
  on day one. Until it does, releases are ad-hoc signed and the README
  must say so plainly, with the exact first-launch steps (right-click →
  Open, or `xattr -dr com.apple.quarantine`). Getting a Developer ID
  and notarising is a **release milestone, not a v1 blocker** (§14 M3
  lists it as "if available"). Never claim "notarised" before it is true.
- **No Mac App Store in v1** (D12): sandboxing would complicate folder/
  file launching and the system-Dock import for zero user benefit here.

---

## 13. Limitations (state these in the README, verbatim in spirit)

- This app cannot remove or truly replace the system Dock; it runs
  alongside it. Hiding the system Dock is the user's own setting.
- No notification badges — macOS does not share Mail/Messages (or most
  app) badges with third-party launchers.
- No window previews or per-window switching — clicking a running app
  activates the app, not a chosen window.
- A dock pinned to a disconnected display is hidden until it returns;
  there is no automatic "fail over to another screen" in v1.
- DisplayLink and some USB-C dock displays can report changing display
  UUIDs; if a pinned dock "loses" its display repeatedly, that is the
  known cause — unpinning (Any display) is the v1 workaround.
- Fullscreen detection is per-display and best-effort for apps using
  custom (non-native) fullscreen; such apps may not trigger hiding.

---

## 14. Milestones & acceptance criteria

Build in order. Each milestone is done only when its acceptance tests
pass on a real Mac — multi-display tests on a real second display,
not by resizing windows on one screen.

### M0 — Scaffold (one hardcoded dock)

- Menu-bar agent, no Dock icon; one floating panel, 5 hardcoded apps,
  real icons, click launches/activates, running dots work.
- **Gate:** the panel must not steal focus, must appear on all Spaces,
  and must survive the host app entering/leaving fullscreen.

### M1 — Real docks (the core)

- Dock CRUD, item add (all 3 ways), reorder, remove + undo, separators,
  JSON persistence with backup + corrupt-file recovery, per-dock icon
  size/spacing/opacity, Settings Docks pane (items + basics).

**Acceptance:**
- A1. Create 3 named docks with different items; quit and relaunch —
  all three return identical in items, order, and position.
- A2. Drag an app, a file, and a folder in from Finder; each opens
  correctly on click; duplicate drop into the same dock is refused.
- A3. Kill the app mid-save (force-quit during edits), corrupt
  `config.json` by hand, relaunch — app recovers from `.bak` or the
  starter dock, never crashes, never shows an empty void.

### M2 — Placement & displays

- Snap/float + orientation flip, drag-to-move + lock, display pinning,
  disconnect/reconnect handling, clamping, auto-hide, fullscreen hide,
  menu-bar dock list + Show/Hide All.

**Acceptance:**
- A4. Snap a dock to each of the 4 edges of a display — orientation and
  auto-hide behaviour are correct on each edge.
- A5. Drag a floating dock half off-screen, relaunch — it returns fully
  visible (clamped) on the same display.
- A6. Enter native fullscreen (e.g. Safari video) on a dock's display
  with fullscreen-hide on — dock hides; exit fullscreen — dock returns.
  With the setting off, the dock stays. 
- A7. **The headline test:** pin a dock to an external display, unplug
  it (dock hides, nothing appears on the main display), replug it —
  dock returns to the same position on that display, unchanged.
- A8. Single-display Mac: all of M1+M2 works, and no display-pinning
  UI is shown.

### M3 — Polish & first release

- First-run flow + system-Dock import, launch at login, General pane
  (export/import config, shortcut), performance budget check (§9),
  README with limitations (§13), GitHub release v0.1.0 (+ Homebrew cask
  PR, notarisation if a Developer ID is available).

**Acceptance:**
- A9. Fresh profile (no config): first run offers import; imported
  items match the system Dock's pinned apps in order; dismissing the
  offer never shows it again.
- A10. 5 docks × 20 items, 1 hour idle: CPU 0% sampled, memory ≤ 60 MB,
  no growth trend (leak check).
- A11. A new user can go from the GitHub README to a running dock in
  under 5 minutes using only the README (test with the release build,
  including the Gatekeeper steps if un-notarised).

---

## 15. Roadmap (v2+, explicitly not v1)

- **Live Dock widget/item** — mirror the system Dock (or just running
  apps) inside one of your docks, updating live.
- **Widgets** — clock, Trash (open/empty, item count), battery, spacer
  variants; each opt-in per dock.
- **Magnification**, custom colours/themes per dock, custom app icons.
- **Folder stacks** — click a folder item to fan out its contents.
- **Collapse mode** — shrink a dock to one button, expand on hover/click.
- **Per-Space docks** and **dock profiles/presets** (switch a whole set
  of docks per workflow, DockFlow-style, without DockFlow).
- **Window previews** on hover — requires Accessibility (and possibly
  Screen Recording) permission, so it lands as an explicit opt-in with
  the permission ask explained, breaking D5 only for users who enable it.
- **Notarised, signed releases** as the default download.
- Import/export *named* config profiles (v1 export/import is one file).

---

## 16. Open decisions (tiny, non-blocking)

1. ~~**App name & repo name**~~ — **Resolved 2026-11-20: Dock+**
   (D13). Remaining check only: confirm GitHub repo name `dock-plus`
   and the Homebrew cask name are available before creating them
   (there is already an unrelated "MultiScreenDock" etc.).
2. **Developer ID / notarisation** — pay for it before v0.1.0, or ship
   ad-hoc first and notarise later? Spec assumes the latter (§12).
3. **Minimum macOS 14 vs 13** — 14 is assumed (D7); dropping to 13 is
   possible but must be decided before M0, not after.
4. Whether the starter dock's first-run import offer defaults to
   importing the user's *running* apps instead, if the plist read fails.
