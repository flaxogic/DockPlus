# Dock+

**Just the macOS Dock — multiplied, with zero bloat.**

[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B%20Sonoma-000000?logo=apple&logoColor=white)](https://github.com/flaxogic/DockPlus/releases)
[![Universal Binary](https://img.shields.io/badge/arch-arm64%20%2B%20x86__64-0A84FF)](https://github.com/flaxogic/DockPlus/releases)
[![Version](https://img.shields.io/badge/version-v0.1.0-34C759)](https://github.com/flaxogic/DockPlus/releases)
[![Zero Permissions](https://img.shields.io/badge/permissions-none%20required-5856D6)](#philosophy)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[Website](https://flaxogic.github.io/DockPlus/) · [Releases](https://github.com/flaxogic/DockPlus/releases) · [Quick Start](#quick-start) · [Build from Source](#build-from-source) · [Complete Guide](INTRO.md) · [Changelog](CHANGELOG.md)

Dock+ is a native, lightweight macOS menu-bar utility that lets you create any number of independent floating or edge-snapped docks across your displays. Built natively with AppKit, SwiftUI, and an Objective-C QuartzCore Liquid Glass rendering engine, Dock+ delivers the authentic look, physics, and feel of the macOS Dock while requiring **zero permissions**, **zero third-party dependencies**, and **zero network access**.

---

## Philosophy

Most dock replacements try to reinvent macOS with heavy overlays, widgets, or invasive Accessibility hacks. Dock+ takes the opposite approach:

- **Native Feel First:** Cosine-wave magnification, launch bounces, hover tooltip pills, 1:1 drag-to-reorder, drag-off removal, right-click context menus, and Liquid Glass optics behave like macOS itself.
- **Zero Permissions Required:** No Accessibility, no Screen Recording, and no Full Disk Access. Dock+ never hooks into other apps or records your screen.
- **Private & Local:** Free forever, open source (MIT), no accounts, no telemetry, and zero background network calls. Everything lives locally on your Mac.
- **Lightweight Menu-Bar Agent:** Runs quietly as an `LSUIElement` menu-bar app with non-activating floating panels (`canBecomeKey = false`) so clicking dock icons never steals focus unexpectedly.

---

## Key Features

- **Unlimited Independent Docks:** Create dedicated docks for Coding, Comms, Design, or anything else. Each dock stores its own pinned **apps, files, folders, and separators**, **icon size** (`32 pt` – `80 pt`), **magnification** (`1.15×` – `2.0×`), **orientation** (`Horizontal` / `Vertical`), **placement** (`Bottom`, `Top`, `Left`, `Right`, or `Floating`), **auto-hide**, **transparency**, **tint color**, and **display UUID pin**.
- **Hardware Liquid Glass:** Direct QuartzCore GPU Signed Distance Field (SDF) refraction, chromatic dispersion, and specular rim highlights on macOS 26/27 — staying 100% active even on non-key floating panels. Customize per-dock **Transparency** (`Opaque` ↔ `Clear`) and **Tint Color** (macOS presets or custom color picker), with automatic `NSVisualEffectView` fallback on macOS 14–25.
- **Authentic Dock Physics:** Smooth cosine-wave magnification with outward neighbor expansion, 1:1 cursor-tracking drag-to-reorder, drag-off removal with **Undo Remove** (`⌘Z`), Retina (`@2x`/`@3x`) `CGImage` icon caching, launch bounces, and instant running-indicator dots via `NSWorkspace` notifications and KVO (no polling).
- **Open Apps Dock:** Designate any single dock in **Manage Docks (`⌘M`)** to display unpinned running apps behind a separator — right-click any open app and choose **Options ▸ Keep in Dock** (or **Keep in Another Dock**) to pin it permanently.
- **Dedicated Move Mode & Magnetic Edge Snapping:** Enter **Move Mode** from the menu bar, dock context menu, or Manage Docks (`Esc` or **Done** exits). Drag within `24 pt` of any screen edge to snap magnetically and auto-align orientation (`Bottom`/`Top` → Horizontal, `Left`/`Right` → Vertical).
- **Completely Invisible Auto-Hide:** Edge-snapped docks with auto-hide enabled slide completely off-screen (`0%` opacity) with zero stray glass sliver, revealing cleanly when your cursor reaches an invisible `2 pt` edge trigger.
- **Native Context Menus & Reversible System Dock Suppression:** Right-click icons for **Options ▸ Keep in Dock**, **Open at Login**, **Move to ▸**, **Copy to ▸**, **Show in Finder**, **Hide**, **Quit**, or **Open**. Optionally enable **Settings → Disable system Dock** to suppress the built-in macOS Dock while Dock+ runs (automatically restoring your previous macOS Dock settings on toggle off or quit).

---

## Installation & First Launch

### Download Prebuilt Release (DMG)

1. Download **`DockPlus-0.1.0.dmg`** from [GitHub Releases](https://github.com/flaxogic/DockPlus/releases).
2. Open the `.dmg` and drag **`DockPlus.app`** into **Applications**.

### First Launch (Ad-Hoc Signed Releases)

Release binaries are currently ad-hoc signed rather than notarised with a paid Apple Developer ID. On first launch of a downloaded build:

1. Right-click **`DockPlus.app`** in `/Applications` and select **Open**, then confirm **Open**; **or**
2. Clear the quarantine attribute in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/DockPlus.app
   ```

---

## Quick Start

Click the **Dock+** icon in the macOS menu bar (`dock.rectangle`) to create docks, toggle individual docks, enter Move Mode, or open management windows:

| Action | Shortcut / Location |
| --- | --- |
| New Dock | Menu Bar → **New Dock** (`⌘N`) |
| Undo Item Removal | Menu Bar / Edit → **Undo Remove** (`⌘Z`) |
| Manage Docks (Items, Size, Glass, Tint, Position) | Menu Bar → **Manage Docks…** (`⌘M`) |
| Settings (Disable system Dock, Import starter items, Login item) | Menu Bar → **Settings…** (`⌘,`) |
| Move Docks / Exit Move Mode | Menu Bar → **Move Docks** · Press **`Esc`** or click **Done** |
| Quit Dock+ | Menu Bar → **Quit Dock+** (`⌘Q`) |

---

## Privacy & Local Storage

Dock+ makes **zero network connections** and collects **zero telemetry**. All configuration is written atomically to:

```text
~/Library/Application Support/DockPlus/docks.json
```

Before every save, the previous valid state is preserved in `docks.json.bak` for automatic corruption recovery.

---

## Build from Source

### Requirements

- **macOS 14.0 (Sonoma) or later** (macOS 26/27 for full hardware SDF Liquid Glass; automatic `NSVisualEffectView` fallback on macOS 14–25)
- **Xcode 16+**
- Zero external packages, CocoaPods, or paid signing identities required (builds as a universal `arm64` + `x86_64` binary)

### Build & Run in Xcode

```bash
git clone https://github.com/flaxogic/DockPlus.git
cd DockPlus
open DockPlus.xcodeproj
```

Select the **DockPlus** scheme and press **`⌘R`** to build and run, or **`⌘U`** to run the unit test suite (`DockPlusTests`).

### Command-Line Build, Test & DMG Packaging

```bash
# Run unit tests (Debug)
xcodebuild -project DockPlus.xcodeproj -scheme DockPlus -configuration Debug -destination 'platform=macOS' test

# Build Universal Release binary (arm64 + x86_64)
xcodebuild -project DockPlus.xcodeproj -scheme DockPlus -configuration Release -destination 'generic/platform=macOS' build

# Build & package Universal Release DMG into dist/
./scripts/build-dmg.sh
```

---

## Known Limitations

- **Runs alongside the built-in macOS Dock:** macOS's `Dock.app` also drives Mission Control, Spaces, Wallpaper, and `⌘⇥`, so it cannot be uninstalled. Use **Settings → Disable system Dock** to suppress the built-in Dock safely while Dock+ is running (restored automatically when you quit).
- **No notification badges:** macOS does not share Mail, Messages, or third-party app badge counts with third-party launchers without restricted APIs.
- **No per-window previews:** Clicking a running app icon activates the app rather than targeting an individual window.
- **Disconnected displays:** A dock pinned to a specific display UUID remains hidden until that display reconnects.
- **DisplayLink / USB-C hubs:** Some DisplayLink adapters or USB-C hubs report changing display UUIDs across reconnects. If a pinned dock does not reappear on reconnect, set its Display to **Primary Display** in **Manage Docks (`⌘M`)**.
- **Fullscreen detection:** Fullscreen hiding is per-display and best-effort for apps using custom (non-native) fullscreen modes.

---

## Documentation & License

- [INTRO.md](INTRO.md) — Complete user guide, module architecture, and design notes.
- [docs/index.html](docs/index.html) — Static release website source (GitHub Pages).
- [CHANGELOG.md](CHANGELOG.md) — Release history.
- [CONTRIBUTING.md](CONTRIBUTING.md) — Development setup and contribution guidelines.
- [SECURITY.md](SECURITY.md) — Security model and vulnerability reporting.
- Released under the **MIT License** — see [LICENSE](LICENSE).
