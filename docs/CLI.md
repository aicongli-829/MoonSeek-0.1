# FileNest CLI Reference

Run commands from the repository root:

```sh
moon run --target native cmd/filenest -- <command> [arguments]
```

Use forward slashes or a quoted native path. Commands that inspect files print structured JSON unless another format is requested.

## Global options

| Option | Purpose |
| --- | --- |
| `--version` | Print the FileNest version. |
| `--config <file>` | Load validated options from JSON. |
| `--rules <file>` | Compile a readable `.fnrules` file. |
| `--yes` | Explicitly authorize `apply` or `undo`. |

`--config` and `--rules` are mutually exclusive.

## Browser workspace

```sh
moon run --target native cmd/filenest -- serve
moon run --target native cmd/filenest -- serve --root "D:/Downloads" --port 4174
```

The server binds to `127.0.0.1`. The default port is `4173`; accepted custom ports are `1024` through `65535`.

## Scan and analyze

```sh
moon run --target native cmd/filenest -- scan "D:/Downloads"
moon run --target native cmd/filenest -- analyze "D:/Downloads" --config examples/downloads.json
```

`scan` returns the inventory and confirmed duplicate groups. `analyze` summarizes categories, extensions, size bands, directories, and reclaimable duplicate space. Neither command moves files.

## Preview and apply

```sh
moon run --target native cmd/filenest -- preview "D:/Downloads" --rules examples/downloads.fnrules
moon run --target native cmd/filenest -- preview "D:/Downloads" --config examples/downloads.json --csv
moon run --target native cmd/filenest -- apply "D:/Downloads" --config examples/downloads.json --yes
```

`preview` creates the same deterministic plan used by `apply`. Without `--yes`, `apply` prints the plan and stops. With `--yes`, FileNest rescans and verifies file fingerprints before starting a journaled transaction.

## Snapshots and differences

```sh
moon run --target native cmd/filenest -- snapshot "D:/Downloads" --output before.json
moon run --target native cmd/filenest -- diff "D:/Downloads" --snapshot before.json
```

A snapshot contains relative paths and file metadata. `diff` reports added, removed, modified, and moved files against the current directory state.

## History and undo

```sh
moon run --target native cmd/filenest -- history "D:/Downloads"
moon run --target native cmd/filenest -- undo "D:/Downloads" BATCH-ID --yes
```

History is stored under the selected root in `.filenest/history`. Undo refuses to overwrite files restored after the original operation and verifies the current files before moving them.

## Safety checklist

1. Run `preview` and inspect every conflict.
2. Keep important folders backed up independently.
3. Do not edit `.filenest` while a transaction is active.
4. Test new rules on a temporary directory before applying them to personal files.
