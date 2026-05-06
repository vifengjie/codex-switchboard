# Privacy

Codex Quota Manager is designed as a local-first macOS utility.

## What The App Stores

- Account metadata such as alias, workspace label, masked email, plan type, authorization state, and priority
- Quota snapshots, usage events, alert events, switch events, audit events, and collector offsets
- Application settings such as thresholds, stale windows, and redaction flags

SQLite data is stored under:

`~/Library/Application Support/Codex Quota Manager/quota-manager.sqlite`

Sensitive secret material is stored in macOS Keychain, not in SQLite.

## What The App Does Not Store

The app must not copy, export, or upload:

- `~/.codex/auth.json`
- OAuth access tokens
- refresh tokens
- cookies
- raw chat content
- code content
- private repository contents

## Telemetry

The app does not send telemetry by default.

## Data Sources

The app reads local Codex JSONL session logs and local Codex state SQLite data to derive quota and usage summaries. It is intended to parse structured usage and rate-limit fields rather than archive full session content.

## Export And Diagnostics

The app can export usage details as CSV or JSON and export a diagnostics JSON summary.

Exports and diagnostics are intended to remain sanitized:

- usage export includes token M, estimated credits, account alias, thread ID or masked title, model, timestamps, and source
- diagnostics export includes configuration summary, source readability, counts, offset summaries, and latest snapshot summary

Exports and diagnostics must not contain token, cookie, auth, chat body, or code body fields.

## Cleanup

The app provides explicit cleanup actions for its own local SQLite data and, when requested, its own Keychain references. Cleanup does not remove or modify Codex internal auth files.
