# MoonMigrate architecture

## Migration data flow

1. The core decodes a manifest and validates identifiers, operations, paths, hashes, and version ranges.
2. The planner reads the installed version and resolves one contiguous route to the requested target.
3. The Native adapter checks the real filesystem without changing it and produces an action preview.
4. Apply acquires a root-local lock and persists every action as `pending` before execution.
5. Each action moves through `running` to `done`, with an atomic journal update at each boundary.
6. The installed version advances only after every action completes.
7. Rollback visits recorded actions in reverse order, restores backups and quarantined files, then restores the old version.

## Package boundaries

- `moonmigrate/core` is deterministic and portable. `migration.mbt` owns manifest types, validation, version routing, and the JSON API. The package also retains FileNest planning algorithms as reusable transaction infrastructure.
- `moonmigrate/core/native` owns filesystem inspection, locking, SHA-256, state, journals, backup paths, execution, and rollback.
- `cmd/moonmigrate` is the primary Native executable.
- `cmd/filenest` and `webui` are legacy demonstration clients for the shared safe-file primitives.

## State layout

```text
.moonmigrate/
  state.json                 installed project and version
  lock                       exclusive apply/rollback lock
  history/<batch>.json       action phases and rollback metadata
  backups/<batch>/<step>     original write/replace files
  quarantine/<batch>/...     obsolete files retained for rollback
```

Manifest paths cannot enter this directory. Journal records omit manifest text payloads; only the paths, hashes, phases, and rollback locations are persisted.

## Safety invariants

- All user paths are portable relative paths under one resolved root.
- Existing symbolic links and directory junctions are rejected during traversal.
- Move and copy destinations use create-new or `rename(..., replace=false)` behavior.
- Optional SHA-256 checks run immediately before the batch is accepted.
- A project identity in `state.json` prevents a different manifest from taking over the same root.
- A running or failed journal blocks a later apply until it is rolled back.
- A completed batch can only roll back when its target is still the installed version.

MoonMigrate records interruption points and supports rollback from a `running` journal. It does not claim database-grade atomicity across arbitrary filesystem and power failures.

## Legacy two-stage transaction engine

FileNest batch renames use a separate `.filenest` state directory and two non-overwriting rename passes:

```text
pending → staged → applying → done
done → undo-staging → undo-staged → restoring → restored
```

This path remains covered by regression tests and demonstrates cyclic rename handling. It is separate from the ordered migration-step executor.

## Verification

- Core tests cover version routing, gap and boundary diagnostics, step validation, and JSON plans.
- Native tests cover SHA-256, path rules, filesystem scanning, and platform time conversion.
- The migration integration test applies all six operation types to real files, checks version state, and rolls the entire batch back.
- Legacy FileNest integration tests continue to cover scan, duplicate confirmation, two-stage apply, and undo.
