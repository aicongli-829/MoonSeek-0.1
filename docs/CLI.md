# MoonMigrate CLI reference

Run commands from the repository root:

```sh
moon run --target native cmd/moonmigrate -- <command> [arguments]
```

Paths may use forward slashes or quoted native separators. Commands print structured JSON so installers and application launchers can consume the result.

## Plan

```sh
moon run --target native cmd/moonmigrate -- migrate-plan ROOT --manifest migrations.json
moon run --target native cmd/moonmigrate -- migrate-plan ROOT --manifest migrations.json --to 2
```

`migrate-plan` reads the installed state, resolves a contiguous version route, validates all manifest steps, and checks the real filesystem. It does not modify the root.

## Apply

```sh
moon run --target native cmd/moonmigrate -- migrate-apply ROOT --manifest migrations.json --yes
moon run --target native cmd/moonmigrate -- migrate-apply ROOT --manifest migrations.json --to 2 --yes
```

Apply requires the explicit `--yes` flag. It repeats preflight under an exclusive lock, writes a journal before mutation, records every action phase, and advances the installed version only after all steps complete.

Without `--yes`, the command prints the preview and exits without applying it.

## Status

```sh
moon run --target native cmd/moonmigrate -- migrate-status ROOT
```

The result contains the project identity, installed version, and history records under `.moonmigrate`.

## Rollback

```sh
moon run --target native cmd/moonmigrate -- migrate-rollback ROOT BATCH-ID --yes
```

Rollback visits actions in reverse order and restores the previous version. A completed batch can only roll back while its target remains installed; this prevents an older batch from crossing newer migrations.

## Exit safety

- Manifest paths cannot escape `ROOT` or enter reserved state directories.
- Existing symbolic links and junctions are rejected.
- Move and copy targets are never replaced.
- A running or failed batch blocks the next apply until it is rolled back.
- Keep `.moonmigrate` with the application data until its rollback window closes.
