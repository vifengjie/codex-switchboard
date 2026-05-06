# Security

## Security Boundary

Codex Quota Manager is intentionally scoped as a local quota and workflow helper.

It must not:

- read, copy, replace, or synchronize `~/.codex/auth.json`
- export OAuth tokens, refresh tokens, or cookies
- archive raw chat content or code content into diagnostics
- perform silent background account rotation

Sensitive secrets that belong to this application are stored in macOS Keychain. SQLite stores only non-secret metadata and optional Keychain references.

## Supported Branch

Security fixes are expected to land on `main`.

## Reporting A Vulnerability

If you discover a security issue, do not open a public issue with sensitive details.

Please report:

- affected commit or branch
- impact summary
- reproduction steps
- whether the issue can expose secret material, account identity, or local session content

If you are using this repository privately, report directly to the maintainer through a non-public channel first.

## Hardening Notes

Current implementation protections:

- local-first storage
- Keychain-backed secret storage
- sanitized usage export
- sanitized diagnostics export
- user-confirmed account switching
- audit trail for switching, export, cleanup, and settings changes

Current limits:

- the app cannot cryptographically prove the active Codex account after a switch
- post-switch verification still relies on official flow completion and observed refreshed snapshots
