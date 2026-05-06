# Codex Quota Manager

Codex Quota Manager is a macOS menu bar app for local Codex quota visibility, token usage review, low-quota alerts, and user-confirmed account switching.

This repository is currently in early M1 stage.

## Development

Requirements:

- macOS
- Swift 6.1 or newer
- Full Xcode is recommended for App packaging. Swift Package build and tests can run with Command Line Tools.

Run tests:

```bash
swift test
```

Build the scaffold:

```bash
swift build
```

Run the menu bar scaffold:

```bash
swift run CodexQuotaManager
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

Current scaffold status:

- Full Xcode is selected.
- `swift build` passes.
- `swift test` passes.
- The menu bar app loads its startup state from SQLite-backed settings and quota snapshot repositories.

Check whether the workspace is ready to enter M1:

```bash
bash tools/check_m1_readiness.sh
```

The script requires full Xcode. If it reports that Command Line Tools are active, install Xcode and run:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Current M1 Slice

Implemented:

- SQLite migration for `app_settings`, `quota_snapshots`, and `schema_migrations`.
- SQLite migration for `accounts`.
- SQLite migration for `audit_events`.
- SQLite migration for `usage_events`.
- `SQLiteSettingsRepository` with default settings bootstrap.
- `SQLiteSnapshotRepository` with latest snapshot read/write.
- `SQLiteAccountRepository` with account list, upsert, lookup, and delete.
- `SQLiteAuditRepository` with audit record and recent event lookup.
- `SQLiteUsageEventRepository` with usage event upsert and recent event lookup.
- App startup storage bootstrap under `~/Library/Application Support/Codex Quota Manager/quota-manager.sqlite`.
- Menu bar unconfigured state: `Cdx 未设置`.
- Management window overview, accounts, and policy tabs are wired to SQLite-backed data.
- Management window audit tab shows local audit events.
- Management window details tab shows local usage events.
- Account add, enable/disable, and delete actions write audit events.
- Policy settings are editable and persisted to SQLite.
- Policy save actions write `settings_update` audit events.

## Privacy Boundary

The MVP is designed as a local-first app. It must not copy, export, or upload OAuth tokens, cookies, `~/.codex/auth.json`, chat content, code content, or private repository contents.
