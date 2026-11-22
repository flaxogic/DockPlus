# Changelog

All notable changes to **Dock+** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-11-22

### Added
- **Unlimited Independent Docks:** Create, rename, show/hide, and delete multiple docks with independent pinned apps, files, folders, and separators.
- **Hardware Liquid Glass Rendering:** Custom QuartzCore GPU Signed Distance Field (SDF) glass engine on macOS 26/27 with per-dock transparency (`Opaque` ↔ `Clear`) and tint color, plus automatic `NSVisualEffectView` fallback on macOS 14–25.
- **Authentic Dock Physics:** Smooth cosine-wave magnification, 1:1 cursor-tracking drag-to-reorder, drag-off removal with Undo (`⌘Z`), Retina `@2x`/`@3x` icon caching, launch bounces, hover tooltip pills, and live running-app indicators.
- **Open Apps Dock:** Designate any single dock to display unpinned running applications behind a separator, with **Options ▸ Keep in Dock** support.
- **Dedicated Move Mode & Magnetic Edge Snapping:** Snap docks to any screen edge (`Bottom`, `Top`, `Left`, `Right`) with automatic orientation alignment, or float freely across displays pinned by display UUID.
- **Invisible Auto-Hide:** Edge-snapped docks slide completely off-screen at `0%` opacity and reveal smoothly via a `2 pt` edge trigger.
- **Reversible System Dock Suppression:** Optional **Settings → Disable system Dock** toggle that automatically restores previous macOS Dock settings on toggle off or app quit.
- **Zero-Permission, Zero-Dependency Architecture:** Native AppKit + SwiftUI + Objective-C QuartzCore universal binary (`arm64` + `x86_64`) with atomic JSON persistence and `.bak` recovery.
- **DMG Packaging Script:** Added `scripts/build-dmg.sh` to build and package universal `.dmg` releases.
