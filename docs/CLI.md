# CLI reference

```text
moon run --target native cmd/moonseek -- <command> [arguments]
```

The default database is `.moonseek/index.json`. Every command accepts `--database PATH`.

## Add or update a root

```text
moonseek index add FOLDER
moonseek index add FOLDER --ext md,txt,mbt
```

The first form indexes filenames for every regular file and content for recognized text formats. `--ext` restricts the entire scan to the listed extensions. Repeating the command incrementally reuses unchanged entries.

## Remove a root

```text
moonseek index remove FOLDER
```

This removes the root from the index and does not modify the source folder.

## Search

```text
moonseek search QUERY --limit 50
```

Quote a multiword query at the shell level when necessary. Query operators include `ext:`, `type:`, `path:`, `root:`, `size:`, `modified:`, negative `-term`, and quoted phrases. The limit is clamped to 1–200.

## Suggestions

```text
moonseek suggest PREFIX --limit 12
```

Suggestions combine matching filenames, frequent indexed terms, extensions, and semantic categories.

## Status and diagnostics

```text
moonseek status
moonseek doctor
```

`status` reports indexed roots and totals. `doctor` verifies format version, document identity, posting bounds and counts, deterministic term order, categories, and aggregate statistics.

## Web interface

```text
moonseek serve --port 4173
```

The port must be between 1024 and 65535. The server listens on `127.0.0.1` and prints the local URL. Press Ctrl+C to stop it.
