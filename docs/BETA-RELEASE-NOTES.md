# Codex Quota Manager Beta Release Notes

## Scope

This beta focuses on local Codex quota visibility and user-confirmed switching workflow on macOS.

## Included

- Menu bar quota status
- Local JSONL and state SQLite collection
- Usage details with filters
- CSV / JSON export
- Multi-account metadata
- User-confirmed switch workflow
- Audit trail
- Local cleanup workflow
- Sanitized diagnostics export

## Not Included

- Silent automatic account rotation
- Direct manipulation of `~/.codex/auth.json`
- Centralized admin backend
- Cross-device aggregation
- Production-ready notarized installer

## Known Limits

- Switching cannot be verified by unofficial credential inspection
- Some environments may require manual confirmation after official login flow
- Diagnostics export currently contains sanitized summary data, not full stack traces

## Install

At the current stage, build and run locally:

```bash
swift build
swift test
swift run CodexQuotaManager
```

## Uninstall

- Quit the app from the menu bar
- Remove the app bundle if you created one
- Optionally remove `~/Library/Application Support/Codex Quota Manager`
- Optionally delete this app's Keychain references using the in-app cleanup flow
