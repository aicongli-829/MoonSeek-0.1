# MoonMigrate roadmap

## 0.3 · Working migration engine

- [x] Versioned JSON manifest and contiguous-chain planning.
- [x] Native dry-run with filesystem preconditions.
- [x] Directory, move, copy, write, replace, and quarantine steps.
- [x] Durable state, per-step journal, backups, and reverse rollback.
- [x] Real-filesystem integration test for apply and rollback.
- [x] Dedicated `moonmigrate` Native executable.

## 0.4 · Recovery and authoring

- [ ] Add explicit resume and reconcile commands for interrupted steps.
- [ ] Generate new manifests with an `init` command.
- [ ] Publish a JSON Schema and editor completion metadata.
- [ ] Add step-level postconditions and a first-occurrence replace mode.
- [ ] Add machine-readable plan output modes for installer integration.

## 0.5 · Cross-platform confidence

- [ ] Run migration integration tests on Windows, Linux, and macOS in CI.
- [ ] Test permission failures, disk exhaustion, and process interruption.
- [ ] Add backup retention and garbage-collection commands.
- [ ] Benchmark manifests with thousands of steps.

## 1.0 · Stable library

- [ ] Freeze manifest format version 1 and CLI compatibility.
- [ ] Publish the reusable core and Native packages to Mooncakes.
- [ ] Publish signed release archives and checksums.
- [ ] Complete recovery, security, and documentation reviews.
