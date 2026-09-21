# MoonMigrate

[简体中文](README.md) | English

**MoonMigrate is a versioned filesystem migration framework written in MoonBit.** It turns application data layout upgrades into reviewable manifests with dry-run planning, precondition checks, durable journals, and batch rollback.

Databases have schema migrations; application directories are often upgraded by one-off scripts. A crash, occupied destination, locally modified file, or broken version chain can leave an installation in an ambiguous mixed state. MoonMigrate provides a reusable MoonBit API and Native CLI for those changes.

## Use cases

- desktop application data and configuration upgrades;
- plugin and editor-extension storage migrations;
- installer and updater resource relocation;
- cache, index, and generated-output layout changes;
- project template and asset-pipeline evolution.

## Implemented

- contiguous version-chain validation and target-version planning;
- `mkdir`, `move`, `copy`, `write`, `replace`, and `quarantine` operations;
- path, file-kind, destination, text, and optional SHA-256 preconditions;
- non-overwriting native execution within a selected root;
- durable version state and per-step journals under `.moonmigrate`;
- reverse-order rollback for completed and interrupted batches;
- a MoonBit Native CLI with no Node.js or npm dependency.

## Quick start

```sh
git clone https://github.com/aicongli-829/MoonMigrate-v1.0.git
cd MoonMigrate-v1.0
moon update
moon run --target native cmd/moonmigrate -- migrate-plan ./demo --manifest examples/moonmigrate.json
moon run --target native cmd/moonmigrate -- migrate-apply ./demo --manifest examples/moonmigrate.json --yes
moon run --target native cmd/moonmigrate -- migrate-status ./demo
moon run --target native cmd/moonmigrate -- migrate-rollback ./demo BATCH-ID --yes
```

See the [migration guide](docs/MIGRATIONS.md) for the manifest schema and rollback rules.

## Validation

```sh
moon fmt --check
moon check --target native
moon test --target native
moon build cmd/moonmigrate --target native --release
```

The test suite covers migration-chain planning and diagnostics, then executes all six operation types against a real temporary directory and rolls the batch back.

MoonMigrate is released under the [MIT License](LICENSE). See the [ecosystem comparison](docs/ECOSYSTEM.md) and [architecture](docs/ARCHITECTURE.md) for design context.
