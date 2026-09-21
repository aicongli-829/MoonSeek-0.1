# Testing and troubleshooting

## Complete verification

```sh
moon update
moon fmt --check
moon check --target native
moon test --target native
moon build cmd/moonmigrate --target native --release
```

The Native suite covers manifest validation, version routing, path safety, SHA-256, real filesystem operations, installed state, journals, and complete rollback. JavaScript checks remain in CI as regression coverage for the portable core and visual transaction example.

## Manual smoke test

Create a disposable directory and copy `examples/moonmigrate.json`. Add only synthetic files that match the optional examples, then run:

```sh
moon run --target native cmd/moonmigrate -- migrate-plan ./smoke --manifest examples/moonmigrate.json
moon run --target native cmd/moonmigrate -- migrate-apply ./smoke --manifest examples/moonmigrate.json --yes
moon run --target native cmd/moonmigrate -- migrate-status ./smoke
moon run --target native cmd/moonmigrate -- migrate-rollback ./smoke BATCH-ID --yes
```

Confirm that planning changes nothing, apply reaches version 2, rollback restores original contents, and migration-created files and empty directories disappear.

## Common failures

### Registry dependency not found

Run `moon update`. A fresh toolchain may not yet have a current Mooncakes registry index.

### Native compiler is unavailable

Install the platform C toolchain. Windows uses Visual Studio Build Tools with the C++ workload; Linux and macOS use a supported system compiler.

### A migration lock remains

Confirm that no MoonMigrate process is running. Inspect `.moonmigrate/history` before removing `.moonmigrate/lock`. Never remove an active lock to run two migrations at once.

### Apply reports an unfinished batch

Inspect the batch shown by `migrate-status`, then use `migrate-rollback ROOT BATCH-ID --yes`. A later apply is intentionally blocked until the partial transition is resolved.

### A hash or text precondition fails

The installed file no longer matches the expected old release. Do not bypass the check automatically. Review the user-modified content and create an explicit migration path when appropriate.

## Reporting failures

Include the operating system, MoonBit version, command, synthetic directory layout, sanitized manifest, and smallest relevant output. Never upload real application data, access tokens, absolute home paths, `.moonmigrate` backups, or private journals.
