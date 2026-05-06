# Contributing

## Development Environment

Requirements:

- macOS
- Swift 6.1 or newer
- Full Xcode is recommended for running and packaging the menu bar app

Common commands:

```bash
swift build
swift test
swift run CodexQuotaManager
```

If you are not in the repository directory:

```bash
swift run --package-path /Users/fengjie/Documents/CodeX/codex-switchboard CodexQuotaManager
```

## Project Layout

- `App/`: menu bar app and management window
- `Sources/Core/`: shared models and business logic
- `Sources/Collectors/`: local data collectors
- `Sources/Storage/`: SQLite and Keychain access
- `Sources/Switch/`: switching workflow logic
- `Sources/Export/`: CSV, JSON, and diagnostics export
- `Tests/`: unit tests
- `Fixtures/`: sanitized sample data

## Contribution Rules

- Keep the app local-first
- Do not add features that read, replace, or export Codex internal auth files
- Do not commit real session logs, tokens, cookies, or private repository content
- Prefer extending existing modules over bypassing them from UI code
- Add or update tests for behavior changes in storage, collectors, switching, or export

## Fixtures

Only sanitized fixtures belong in `Fixtures/`.

Do not add:

- real user JSONL logs
- raw chat content
- code content
- tokens or auth fields

## Pull Requests

Before opening a PR:

1. Run `swift test`
2. Confirm exports and diagnostics remain sanitized
3. Confirm any new account or switching behavior is audited
4. Update `README.md` or docs when the user-facing scope changes

## Issue Reports

For user-visible bugs, prefer the GitHub bug template under:

- `.github/ISSUE_TEMPLATE/bug_report.md`

Bug reports should include:

- commit SHA
- macOS version
- reproduction steps
- whether sanitized diagnostics export is attached
