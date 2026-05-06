# Codex Quota Manager

Codex Quota Manager is a macOS menu bar app for local Codex quota visibility, token usage review, low-quota alerts, and user-confirmed account switching.

The repository is currently in the `M5` management, export, cleanup, and diagnostics slice. `M1` to `M5` are implemented on `main`; `M6` will focus on packaging, release documents, and beta acceptance hardening.

## What It Does

- Shows current Codex `5H` and `1W` remaining quota in the macOS menu bar.
- Parses local Codex JSONL logs and state SQLite data without copying chat or code content.
- Tracks token usage, estimated credits, quota snapshots, settings, and audit events in local SQLite.
- Supports multi-account metadata, enable/disable, priority, authorization state, and Keychain-backed secret references.
- Provides a user-confirmed switching workflow:
  open official login or account-selection flow, wait for user confirmation, refresh the target account snapshot, and audit the result.

## Current Scope

Implemented on `main`:

- `M1`: local storage bootstrap, menu bar scaffold, management window skeleton, settings persistence.
- `M2`: local collector pipeline, JSONL parsing, Codex state SQLite reading, quota snapshot refresh.
- `M3`: estimated credits, quota alert policy, notifications, recommendation engine.
- `M4`: account metadata expansion, Keychain storage, switch preflight, switch state machine, switch events, user-confirmed switch flow, account add/edit form.
- `M5`: usage detail filters, CSV/JSON export, audit filters, local cleanup workflow, sanitized diagnostics export.

Not implemented yet:

- Silent or background automatic account rotation.
- Reading, copying, replacing, exporting, or syncing `~/.codex/auth.json`.
- Centralized dashboard, enterprise control plane, or multi-device aggregation.
- Release packaging, notarization, and `.dmg` distribution.
- Full `PRIVACY`, `SECURITY`, `CONTRIBUTING`, and release-note hardening.

## Run Locally

Requirements:

- macOS
- Swift 6.1 or newer
- Full Xcode is recommended for app packaging; SwiftPM build and test can run with Command Line Tools

Build:

```bash
swift build
```

Test:

```bash
swift test
```

Run the menu bar app:

```bash
swift run CodexQuotaManager
```

If you are not already in the repo directory:

```bash
swift run --package-path /Users/fengjie/Documents/CodeX/codex-switchboard CodexQuotaManager
```

In restricted local environments, SwiftPM may need writable cache paths:

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/codex-switchboard-clang-module-cache \
  swift build \
  --disable-sandbox \
  --cache-path /tmp/codex-switchboard-swiftpm-cache \
  --config-path /tmp/codex-switchboard-swiftpm-config \
  --security-path /tmp/codex-switchboard-swiftpm-security \
  --scratch-path /tmp/codex-switchboard-build-only \
  --manifest-cache local
```

Current local verification baseline:

- `swift build` passes
- `swift test` passes with 47 tests

## How To Use

1. Start the app with `swift run CodexQuotaManager`.
2. Find the `Cdx ...` status item in the macOS menu bar.
3. Open the management window from the menu bar menu.
4. In the `账号` tab, add or edit account metadata.
5. Use `切换` to enter the user-confirmed switch flow:
   the app runs preflight checks, opens the official login or account-selection flow, waits for your confirmation, then refreshes the target snapshot and writes audit records.

## Storage And Privacy

- SQLite path:
  `~/Library/Application Support/Codex Quota Manager/quota-manager.sqlite`
- Sensitive secrets are stored in macOS Keychain, not in SQLite.
- The app is local-first and does not upload telemetry by default.
- The app must not copy, export, or upload OAuth tokens, cookies, `~/.codex/auth.json`, chat content, code content, or private repository contents.

## Project Structure

- [App](/Users/fengjie/Documents/CodeX/codex-switchboard/App): menu bar app, management window, notifications, local refresh service
- [Sources/Core](/Users/fengjie/Documents/CodeX/codex-switchboard/Sources/Core): models, quota engine, rate card, policy, recommendation
- [Sources/Collectors](/Users/fengjie/Documents/CodeX/codex-switchboard/Sources/Collectors): local JSONL and Codex state collectors
- [Sources/Storage](/Users/fengjie/Documents/CodeX/codex-switchboard/Sources/Storage): SQLite store, repositories, Keychain store
- [Sources/Switch](/Users/fengjie/Documents/CodeX/codex-switchboard/Sources/Switch): switch provider abstraction and switch coordinator
- [Tests](/Users/fengjie/Documents/CodeX/codex-switchboard/Tests): core, collector, storage, and switch tests
- [docs](/Users/fengjie/Documents/CodeX/codex-switchboard/docs): requirements, PRD, technical solution, and development plan

## Key Docs

- [TECH-001](/Users/fengjie/Documents/CodeX/codex-switchboard/docs/04-technical-solution/TECH-001-architecture-and-implementation-options.md)
- [DEV-001](/Users/fengjie/Documents/CodeX/codex-switchboard/docs/05-development-plan/DEV-001-mvp-task-breakdown.md)
- [REQ-001](/Users/fengjie/Documents/CodeX/codex-switchboard/docs/02-requirements/REQ-001-codex-multi-account-quota-management.md)
- [PRD-001](/Users/fengjie/Documents/CodeX/codex-switchboard/docs/03-product-design/PRD-001-product-design-overview.md)
- [PRIVACY.md](/Users/fengjie/Documents/CodeX/codex-switchboard/PRIVACY.md)
- [SECURITY.md](/Users/fengjie/Documents/CodeX/codex-switchboard/SECURITY.md)
- [CONTRIBUTING.md](/Users/fengjie/Documents/CodeX/codex-switchboard/CONTRIBUTING.md)

## Known Limits

- The app can assist switching, but it cannot prove account identity through unofficial credential inspection.
- Post-switch verification currently relies on official flow completion plus refreshed observed snapshots.
- Packaging, notarization, and release artifacts are not finished yet.
