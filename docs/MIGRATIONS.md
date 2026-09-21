# MoonMigrate manifest guide

## Document shape

A manifest is UTF-8 JSON with a stable format version, one project identifier, and an ordered migration history:

```json
{
  "formatVersion": 1,
  "project": "sample-app",
  "migrations": [
    {
      "id": "layout-v1",
      "fromVersion": 0,
      "toVersion": 1,
      "description": "Move settings into the new layout.",
      "steps": []
    }
  ]
}
```

Project, migration, and step identifiers accept letters, digits, `.`, `-`, and `_`. Each `fromVersion` can have only one successor. A plan must reach the requested target through contiguous migration boundaries.

## Operations

| Operation | Required fields | Effect | Rollback |
|---|---|---|---|
| `mkdir` | `path` | Create a directory tree | Remove the created empty directory |
| `move` | `from`, `to` | Move one regular file without replacement | Move it back |
| `copy` | `from`, `to` | Copy one regular file without replacement | Remove the copy |
| `write` | `path`, `content` | Create or replace a UTF-8 file | Restore the backup or remove the new file |
| `replace` | `path`, `find`, `replace` | Replace all matching UTF-8 text | Restore the byte-for-byte backup |
| `quarantine` | `from` | Move an obsolete file into private storage | Restore it to its original path |

Set `optional: true` when an old installation may legitimately lack the source or replacement text. Optional steps are recorded as skipped; other validation errors stop the whole batch before its first change.

Add `expectedSha256` to a file operation to bind it to known old content. The value is a lowercase 64-character SHA-256 digest.

## Planning and execution

```sh
moon run --target native cmd/moonmigrate -- migrate-plan ROOT --manifest MANIFEST
moon run --target native cmd/moonmigrate -- migrate-plan ROOT --manifest MANIFEST --to 2
moon run --target native cmd/moonmigrate -- migrate-apply ROOT --manifest MANIFEST --to 2 --yes
```

Planning reads the current `.moonmigrate/state.json`, resolves a contiguous route, and checks the real filesystem. It makes no changes. Apply repeats the plan under an exclusive lock, stores an action journal, then advances the version only after every step finishes.

The state directory is reserved. Manifest paths cannot target `.moonmigrate`, `.git`, build output, dependency directories, absolute locations, parent traversal, or symbolic links.

## Status and rollback

```sh
moon run --target native cmd/moonmigrate -- migrate-status ROOT
moon run --target native cmd/moonmigrate -- migrate-rollback ROOT BATCH-ID --yes
```

Rollback visits actions in reverse order. Original files changed by `write` and `replace` are kept under `.moonmigrate/backups/<batch-id>` until the batch is rolled back or an external retention policy removes the history. Quarantined files remain recoverable under `.moonmigrate/quarantine`.

If a process stops during a step, its journal remains `running` and shows the last action as `running`. The rollback command accepts this status and reconciles from the paths that exist. Inspect the journal before manually changing any state file.

## Current boundaries

- Operations target regular files and directories; symbolic links are rejected.
- `replace` operates on UTF-8 text and replaces every exact occurrence.
- Rollback of `mkdir` requires the directory to be empty after later actions are reversed.
- One manifest represents a linear version history. Branching and downgrade manifests are future work.
