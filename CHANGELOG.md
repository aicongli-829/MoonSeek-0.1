# Changelog

All notable FileNest changes are recorded here. The project follows [Semantic Versioning](https://semver.org/) after the first public release.

## Unreleased

### Planned

- Cross-platform end-to-end validation on Windows, Linux, and macOS.
- Scan progress for large directories and large files.
- Runtime language switching for the browser workspace.

## 0.2.0 - 2026-09-16

### Added

- MoonBit Native directory scanning, SHA-256 hashing, and exact duplicate confirmation.
- Two-stage file transactions with synchronous journals, history, and batch undo.
- Native CLI commands for scanning, analysis, preview, apply, snapshots, diffs, history, and undo.
- A local HTTP server and a browser workspace implemented in MoonBit.
- Built-in and user-defined organization templates.
- Native integration tests that move and restore real temporary files.

### Changed

- Migrated the runtime, server, CLI, browser state, and browser rendering from handwritten JavaScript to MoonBit.
- Updated the module manifests to the current `moon.mod` and `moon.pkg` formats.
- Added English project documentation while keeping Chinese as the default browser language.

### Removed

- Node.js and npm runtime dependencies.
- Tracked handwritten `.js` and `.mjs` files.

## 0.1.0 - 2026-09-15

### Added

- Deterministic classification, renaming, conflict detection, reports, snapshots, and rule parsing.
- Initial local browser interface and open-source project documentation.
