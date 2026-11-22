# Contributing to Dock+

Thanks for your interest in contributing to **Dock+**!

## Guiding Principles

Before proposing a feature or pull request, keep Dock+'s core philosophy in mind:

- **Zero Permissions:** Changes must never require Accessibility, Screen Recording, or Full Disk Access permissions.
- **Zero External Dependencies:** Keep the project self-contained using Apple's native frameworks (`AppKit`, `SwiftUI`, `QuartzCore`, `ServiceManagement`).
- **Private & Local:** No analytics, telemetry, or network calls.
- **Native Feel:** Match macOS Dock interactions, animations, and HIG conventions closely.

## Development Setup

1. Fork and clone the repository.
2. Open `DockPlus.xcodeproj` in **Xcode 16+** on **macOS 14.0+**.
3. Select the **DockPlus** scheme and press `⌘R` to run, or `⌘U` to run the test suite (`DockPlusTests`).

### Running Tests from the Command Line

```bash
xcodebuild -project DockPlus.xcodeproj -scheme DockPlus -configuration Debug -destination 'platform=macOS' test
```

### Building a Release DMG

```bash
./scripts/build-dmg.sh
```

## Submitting Pull Requests

1. Create a feature or fix branch from `main` (e.g., `fix/edge-snap-offset` or `feat/keyboard-nav`).
2. Keep changes focused and add unit tests in `DockPlusTests/` for geometry, persistence, or model logic.
3. Ensure `xcodebuild ... test` passes with zero warnings or failures.
4. Open a pull request with a clear description of the motivation, behavior changes, and macOS version tested.

## Reporting Bugs

Please open an issue using the **Bug Report** template and include:
- Your macOS version and Mac architecture (`arm64` / `x86_64`)
- Display setup (single/multi-monitor, scaling, DisplayLink/hubs if applicable)
- Exact steps to reproduce
