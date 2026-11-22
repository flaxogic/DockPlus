# Security Policy

## Supported Versions

| Version | Supported |
| --- | --- |
| `0.1.x` | Yes |

## Security & Privacy Model

Dock+ is designed to minimize attack surface by construction:

- Requires **zero macOS privacy permissions** (no Accessibility, Screen Recording, or Full Disk Access).
- Makes **zero network connections** and includes no telemetry or auto-updater executing remote payloads.
- Stores configuration locally in `~/Library/Application Support/DockPlus/docks.json`.

## Reporting a Vulnerability

If you discover a security issue, please do **not** open a public issue. Instead, report it privately via GitHub Security Advisories on this repository, including steps to reproduce and affected macOS versions.
