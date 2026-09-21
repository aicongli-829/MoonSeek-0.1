# MoonMigrate necessity and value

## The repeated problem

Applications evolve more than executable code. New releases relocate settings, split data directories, rename cache keys, seed new resources, and retire incompatible indexes. Teams frequently implement these changes as one-off shell or application-startup scripts.

Those scripts are deceptively risky because they run against state the developer does not control. A user may skip releases, edit a configuration file, restore only part of a backup, or already have a path that the new version wants. A process can stop after step three of six. Without a version route, preconditions, a journal, and reverse actions, the next launch cannot reliably distinguish old, new, and partially migrated state.

## Reusable contribution

MoonMigrate turns that repeated application concern into MoonBit infrastructure:

| Layer | Contribution |
|---|---|
| Deterministic core | Manifest decoding, path rules, version-chain validation, target routing, flattened plans |
| Native preflight | Real file kinds, occupancy, UTF-8 text conditions, optional SHA-256 checks |
| Executor | Non-overwriting operations, lock, backups, quarantine, per-step phases |
| Recovery | Installed-version state, interrupted-journal detection, reverse rollback |
| Interface | Native CLI plus JSON API for installers and MoonBit applications |

The same mechanism applies to desktop software, plugins, local services, CLI caches, indexes, project templates, and asset pipelines. It is independent of any one folder taxonomy or UI.

## Executable evidence

The Native integration test creates an isolated application directory and executes:

1. a versioned directory creation;
2. a legacy-file move;
3. a binary copy;
4. a new version marker write;
5. an existing configuration replacement with backup;
6. obsolete-file quarantine.

It verifies version 1, then rolls the batch back and checks that original contents and locations are restored and created files are gone. Core tests separately cover broken chains, non-boundary targets, unsafe paths, and deterministic plan output.

Run the evidence with:

```sh
moon test --target native
```

## Scope boundary

MoonMigrate is not a database migration engine and does not interpret application schemas. It supplies the filesystem transition layer on which an application-specific migrator can depend. Current format version 1 is linear and file-oriented; branched histories, structured document transforms, and database coordination remain future work.
