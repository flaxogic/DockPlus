# Dock+ — Introduction & Complete Guide

**Just the macOS Dock — multiplied, with zero bloat.**

Dock+ is a native, lightweight macOS menu-bar utility that lets you create any number of independent floating or edge-snapped docks across your displays. Built natively with AppKit, SwiftUI, and an Objective-C QuartzCore Liquid Glass rendering engine, Dock+ delivers the authentic look, physics, and feel of the macOS Dock while requiring **zero permissions**, **zero third-party dependencies**, and **zero network access**.

---

## Philosophy

Most dock replacements try to reinvent macOS with heavy overlays, themes, widgets, or invasive Accessibility hacks. Dock+ takes the opposite approach:

- **Native Feel First:** Every interaction — magnification waves, launch bounces, hover pills, drag-to-reorder, drag-off removal, right-click context menus, and Liquid Glass optics — behaves like macOS itself.
- **Zero Permissions Required:** No Accessibility, no Screen Recording, and no Full Disk Access. Dock+ never hooks into other apps or records your screen.
- **Private & Local:** Free, open-source (MIT), no accounts, no telemetry, no background network calls. Everything lives locally in a single human-readable JSON file.
- **Lightweight Menu-Bar Agent:** Runs quietly as an `LSUIElement` menu-bar app with non-activating floating panels (`canBecomeKey = false`) so clicking dock icons never steals focus unexpectedly or disrupts your workflow.

---

## Key Features

### 1. Unlimited Independent Docks
Create dedicated docks tailored to how you work — for example, a **Coding** dock on the bottom edge, a **Comms** dock snapped to the right edge, and a **Design** dock floating on a secondary monitor. Each dock independently stores:
- Its own pinned **apps, files, folders, and separators**
- **Icon size** (`32 pt` – `80 pt`)
- **Magnification** toggle and zoom scale (`1.15×` – `2.0×`)
- **Orientation** (`Horizontal` or `Vertical`)
- **Placement** (`Bottom`, `Top`, `Left`, `Right` snapped to a screen edge, or `Floating` anywhere)
- **Auto-hide** behavior (for edge-snapped docks)
- **Individual Transparency** and **Tint Color**
- **Display pinning** by hardware display UUID

### 2. Authentic Hardware Liquid Glass
Dock+ recreates Apple's macOS 26/27 Liquid Glass directly on QuartzCore's GPU-accelerated Signed Distance Field (SDF) pipeline (`CABackdropLayer` + `CASDFLayer` + `CASDFElementLayer` + `CASDFOutputEffect` + `CAFilter("glassBackground")` + `CASDFKeyFillHighlightEffect` + `vibrantColorMatrix`):
- **Real-Time Optical Refraction & Dispersion:** Background wallpapers and windows bend along the continuous squircle edges with subtle chromatic dispersion and iridescent specular rim catchlights.
- **Always Active:** Unlike public `NSGlassEffectView` (which dims to an inactive frosted haze on non-key floating panels), Dock+'s custom QuartzCore engine stays 100% active and crystal-clear even while you work in other apps.
- **Per-Dock Transparency & Tint Color:** Customize each dock individually in **Manage Docks (`⌘M`)** with a unified **Transparency** slider (`Opaque` ↔ `Clear`, smoothly scaling both glass density and optical blur from zero-blur clear glass to frosted depth) and **Tint Color** (one-click macOS-style presets or any custom color via the native `ColorPicker`).
- **Light & Dark Mode + macOS 14–25 Compatibility:** Automatically adapts to system appearance changes and gracefully falls back to `NSVisualEffectView` on macOS 14–25.

### 3. Authentic Dock Physics & Interactions
- **Cosine-Wave Magnification:** Hovering over icons triggers a smooth macOS-style magnification wave with outward neighbor expansion and transparent bloom headroom so magnified icons never clip.
- **1:1 Cursor-Tracking Drag & Reorder:** Drag any app, file, folder, or separator smoothly along the dock while neighboring items glide out of the way.
- **Drag-Off Removal with Undo:** Drag an item away from the dock to see a **"Release to Remove"** pill; if you change your mind, restore it instantly with **Undo Remove** from the menu bar or Manage Docks.
- **Retina-Crisp Icons & Feedback:** Multi-scale (`@2x`/`@3x`) `CGImage` icon caching with tactile press darkening, spring launch bounce for non-running apps, instant hover label pills, and live running-indicator dots.
- **Instant Running-App Tracking:** Powered by `NSWorkspace` launch/termination notifications and KVO on `runningApplications` with immediate terminated-PID exclusion — no polling delays.

### 4. Open Apps Dock
Choose any single dock in **Manage Docks** to act as your **Open Apps** dock (or select **Don't Show**). Running applications that aren't pinned to any dock automatically appear on that dock behind a clean separator — just like the right side of the macOS Dock — and disappear the instant they quit. Right-click any open app and select **Options ▸ Keep in Dock** (or **Keep in Another Dock**) to pin it permanently.

### 5. Dedicated Move Mode & Magnetic Edge Snapping
Avoid accidental dock drags while clicking icons:
- Enter **Move Mode** from the menu bar (**Move Docks**), from a dock's right-click menu (**Move Dock**), or from **Manage Docks**.
- A floating Liquid Glass banner (**"Drag dock to move — Done"**) appears above the dock (`Esc` or **Done** exits Move Mode).
- Dragging within `24 pt` of any screen edge magnetically snaps the dock and automatically aligns its orientation (`Bottom`/`Top` → Horizontal, `Left`/`Right` → Vertical).
- You can also snap or float any dock directly via **Snap to Edge ▸ Bottom / Top / Left / Right / Floating**.

### 6. Completely Invisible Auto-Hide
When **Automatically hide and show** is enabled on an edge-snapped dock, the dock slides completely off-screen (`10 pt` past the screen edge at `0%` opacity) so zero stray glass sliver remains visible. A transparent `2 pt` edge trigger window sits silently at the screen edge to reveal the dock smoothly the moment your cursor touches it.

### 7. Native macOS Dock Context Menus
Right-clicking any dock icon opens the familiar macOS Dock menu layout:
- **Options ▸**
  - **Keep in Dock** (checkmarked when pinned; pins transient open apps or removes pinned items)
  - **Open at Login** (toggle auto-launch at login for any app)
  - **Move to ▸** / **Keep in Another Dock ▸** (transfer items between docks)
  - **Copy to ▸** (duplicate an item to another dock)
  - **Show in Finder**
- **Hide** & **Quit** (for running apps) or **Open** (for non-running apps, files, and folders)

Right-clicking empty dock space or a separator gives quick access to **Add Items…**, **Add Separator**, **Move Dock**, **Snap to Edge**, **Switch Orientation**, **Magnification**, **Automatically Hide and Show**, **Manage Docks…**, **New Dock**, and **Delete This Dock**.

---

## Quick Start Guide

### Menu Bar Controls
Click the Dock+ icon in the macOS menu bar to:
- Create a **New Dock**
- Toggle visibility of individual docks
- Enter or exit **Move Docks** mode
- **Show / Hide All Docks** at once
- **Undo Remove** after removing an item
- Open **Manage Docks… (`⌘M`)** or **Settings… (`⌘,`)**
- **Quit Dock+ (`⌘Q`)**

### Manage Docks (`⌘M`)
- **Left Sidebar:** View all docks with live item counts and quick visibility eyes, pick which dock displays **Open Apps**, create (`+`) or delete (`-`) docks, and toggle **Move Docks**.
- **Right Detail Pane:**
  - **Items Bar:** Preview every pinned item and separator — drag chips left/right to reorder, hover any chip and click **`×`** to remove, or use **Add Items…** and **Add Separator**.
  - **General:** Rename the dock, adjust **Size**, and configure **Magnification** toggle and zoom scale.
  - **Appearance:** Tune per-dock **Transparency** (`Opaque` ↔ `Clear`) and **Tint Color** (presets or custom color picker).
  - **Position:** Pick **Snap to Edge**, trigger **Move Dock**, switch **Horizontal / Vertical** orientation, and toggle **Automatically hide and show**.

### Settings (`⌘,`)
- **Disable system Dock:** Suppresses the built-in macOS Dock while Dock+ is running (keeping Mission Control, Spaces, Wallpaper, and `⌘⇥` intact) and automatically restores your exact previous macOS Dock settings when toggled off or when Dock+ quits.
- **Start new docks from current Dock:** Optionally seed every newly created dock with the pinned apps from your macOS Dock (one-time copy from `com.apple.dock.plist`).
- **Launch Dock+ at login:** Register Dock+ to start automatically when you log in via `SMAppService`.

---

## Architecture & Project Structure

Dock+ is organized cleanly into focused, zero-dependency modules:

```text
Dock+/
├── DockPlus/
│   ├── App/
│   │   ├── main.swift                        # Main-actor entry point
│   │   ├── AppDelegate.swift                 # App lifecycle, login-item launch, window wiring
│   │   └── MenuController.swift              # Menu-bar NSStatusItem & actions
│   ├── Docks/
│   │   ├── DockManager.swift                 # Central state, CRUD, multi-dock coordination
│   │   ├── DockPanelController.swift         # Non-activating floating NSPanel per dock
│   │   ├── DockGeometry.swift                # Pure layout, snapping, magnification & auto-hide math
│   │   └── AutoHideController.swift          # Edge-reveal & hide delay state machine
│   ├── Model/
│   │   ├── AppConfig.swift                   # Global settings (glassBlur, openAppsDockID, login apps)
│   │   ├── DockConfig.swift                  # Per-dock config (items, size, magnification, transparency, tint)
│   │   ├── DockItem.swift                    # App, file, folder, and separator item model
│   │   └── ConfigStore.swift                 # Atomic JSON persistence + .bak recovery
│   ├── Services/
│   │   ├── DisplayObserver.swift             # Multi-monitor UUID & visible-frame tracking
│   │   ├── IconCache.swift                   # Retina @2x/@3x CGImage icon cache + file watchers
│   │   ├── Launcher.swift                    # App/file/folder launch, activate, hide, quit, Finder reveal
│   │   ├── LaunchAtLoginService.swift        # SMAppService login registration
│   │   ├── RunningAppObserver.swift          # Instant NSWorkspace + KVO running-app observer
│   │   ├── SystemDockController.swift        # Reversible system Dock suppression & restoration
│   │   └── SystemDockReader.swift            # One-time import from ~/Library/Preferences/com.apple.dock.plist
│   ├── Views/
│   │   ├── LiquidGlassCore.h / .m            # Objective-C QuartzCore SDF Liquid Glass engine
│   │   ├── LiquidGlassView.swift             # Swift NSView host, appearance mapping & macOS 14–25 fallback
│   │   ├── DockItemStripView.swift           # Icon strip, cosine magnification, drag-reorder & drop handling
│   │   ├── DockItemView.swift                # Individual icon/separator rendering, press & bounce physics
│   │   ├── DockTooltipWindow.swift           # Floating Liquid Glass hover label pill
│   │   ├── DockMoveBannerWindow.swift        # Floating Liquid Glass Move Mode banner
│   │   ├── DockEdgeTriggerWindow.swift       # Invisible 2 pt screen-edge trigger for auto-hide
│   │   └── Settings/
│   │       ├── ManageDocksWindowController.swift
│   │       ├── ManageDocksView.swift         # Sidebar + per-dock items, size, appearance & position editor
│   │       ├── SettingsWindowController.swift
│   │       └── SettingsView.swift            # Global Liquid Glass Blur & General preferences
│   ├── DockPlus-Bridging-Header.h            # Bridges LiquidGlassCore.h to Swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
├── DockPlusTests/
│   ├── ConfigStoreTests.swift                # Persistence, backup recovery & plist parsing tests
│   └── DockGeometryTests.swift               # Sizing, snapping, clamping & auto-hide geometry tests
└── DockPlus.xcodeproj
```

### Persistence & Recovery
All configuration is saved atomically to:
```text
~/Library/Application Support/DockPlus/docks.json
```
Before each write, the previous valid configuration is backed up to `docks.json.bak`. If the primary file is ever corrupted, Dock+ automatically recovers from the backup (or creates a clean starter dock if neither is readable).

---

## Building & Testing from Source

### Requirements
- **macOS 14.0 (Sonoma) or later** (macOS 26/27 for full hardware SDF Liquid Glass; automatic `NSVisualEffectView` fallback on macOS 14–25)
- **Xcode 16+**
- No external packages, CocoaPods, or paid signing certificates required (builds ad-hoc signed as a universal `arm64` + `x86_64` binary)

### Build & Run in Xcode
```bash
open DockPlus.xcodeproj
```
Select the **DockPlus** scheme and press **`⌘R`** to run or **`⌘U`** to run the unit test suite.

### Command-Line Build & Test
```bash
# Run unit tests (Debug)
xcodebuild -project DockPlus.xcodeproj -scheme DockPlus -configuration Debug -destination 'platform=macOS' test

# Build Universal Release binary (arm64 + x86_64)
xcodebuild -project DockPlus.xcodeproj -scheme DockPlus -configuration Release -destination 'generic/platform=macOS' build
```

---

## Known Limitations & Notes

- **Built-in macOS Dock:** macOS's `Dock.app` also drives Mission Control, Spaces, Wallpaper, and `⌘⇥`, so it cannot be uninstalled. Enable **Settings → Disable system Dock** to suppress the built-in Dock completely while Dock+ is running (with automatic restoration on quit).
- **No Notification Badges:** macOS does not expose Dock badge counts for Mail, Messages, or other third-party apps without restricted APIs.
- **Ad-Hoc Signed Releases:** If opening a downloaded un-notarized build for the first time, right-click **DockPlus.app → Open** (or run `xattr -dr com.apple.quarantine /Applications/DockPlus.app`).
- **Disconnected Displays:** A dock pinned to a disconnected monitor stays safely hidden and automatically reappears in place when that display is reconnected.

---

## License

MIT — see [LICENSE](LICENSE).
