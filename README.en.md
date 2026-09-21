# FileNest

English | [简体中文](README.md)

FileNest Core is a safe filesystem batch-processing and recoverable transaction engine written in MoonBit. The local FileNest workspace and CLI are complete example applications for classification, batch renaming, duplicate detection, safe previews, and batch undo.

The planning engine, native filesystem adapter, SHA-256 implementation, transaction journal, CLI, local HTTP server, and browser behavior are all written in MoonBit. HTML and CSS provide page structure and styling. MoonBit generates the browser JavaScript during the build, and the generated file stays in the ignored `_build` directory. File contents never leave the computer.

See the [value and validation evidence](docs/VALUE_PROOF.md) for the ecosystem gap, reusable scenarios, and the 1,200-file synthetic test.

## Features

- **File classification:** Organize by file type, modification month, type and month, custom extension rules, or keyword rules.
- **Safe batch engine:** Deterministic plans, conflict diagnostics, two-stage staging, fingerprint checks, and batch journals.
- **Batch renaming:** Add prefixes and suffixes, remove or replace text, normalize spaces and case, add naturally ordered numbers, and apply regular expressions.
- **Duplicate detection:** Group candidates by size and SHA-256, then confirm matches byte for byte.
- **Safe preview:** Review source paths, destinations, conflicts, and invalid entries before changing files. Existing targets are never overwritten.
- **Transactions and undo:** Stage every move, synchronously journal each step, support rename cycles, and restore an entire batch.
- **Analysis and snapshots:** Inspect storage use, identify reclaimable duplicate space, and compare added, removed, modified, or moved files.
- **Two interfaces:** Use the local browser workspace or the native CLI with the same MoonBit core.
- **Reports:** Export previews as CSV, JSON, or Markdown.
- **Readable rules:** Store scan, classification, and rename pipelines in commented `.fnrules` files.

## Requirements

Install the [MoonBit toolchain](https://www.moonbitlang.com/download). FileNest does not require Node.js and has no npm dependencies.

The Native target may use Visual Studio Build Tools on Windows and the system C toolchain on Linux or macOS.

## Start the browser workspace

```sh
git clone https://github.com/aicongli-829/FileNest.git
cd FileNest
moon update
moon build webui --target js --release
moon run --target native cmd/filenest -- serve
```

Open `http://127.0.0.1:4173`. The server only listens on the loopback interface. To select an initial folder or another port:

```sh
moon run --target native cmd/filenest -- serve --root "D:/Downloads" --port 4174
```

## Command line

```sh
moon run --target native cmd/filenest -- --help
moon run --target native cmd/filenest -- scan "D:/Downloads"
moon run --target native cmd/filenest -- analyze "D:/Downloads"
moon run --target native cmd/filenest -- preview "D:/Downloads" --config examples/downloads.json
moon run --target native cmd/filenest -- preview "D:/Downloads" --rules examples/downloads.fnrules --csv
moon run --target native cmd/filenest -- apply "D:/Downloads" --config examples/downloads.json --yes
moon run --target native cmd/filenest -- snapshot "D:/Downloads" --output before.json
moon run --target native cmd/filenest -- diff "D:/Downloads" --snapshot before.json
moon run --target native cmd/filenest -- history "D:/Downloads"
moon run --target native cmd/filenest -- undo "D:/Downloads" BATCH-ID --yes
```

`scan` and `preview` do not move files. `apply` requires `--yes` and rescans the workspace to verify file fingerprints before execution.

## Development

```sh
moon update
moon fmt --check
moon check --target js
moon test --target js
moon build webui --target js --release
moon check --target native
moon test --target native
moon build cmd/filenest --target native --release
```

The test suite covers sorting, classification, renaming, path validation, configuration, reports, analytics, snapshots, rule parsing, transaction state, SHA-256, and Windows timestamp conversion. Native integration tests scan a temporary folder, confirm duplicate contents, apply a real transaction, and undo it.

## Project layout

```text
/*.mbt             Deterministic MoonBit core library
/native/*.mbt      Filesystem scanning, SHA-256, transactions, HTTP server, and CLI
/webui/*.mbt       Browser state, rule editing, rendering, and request orchestration
/cmd/filenest      MoonBit Native executable entry point
/web               Static HTML and CSS
/examples          JSON and .fnrules examples
/docs              Architecture and provenance notes
```

`examples/` includes rules for downloads, photos, coursework, repository migrations, and dataset preprocessing. Always run `preview` before applying a new rule.

The repository tracks no handwritten `.js` or `.mjs` files. Run `moon build webui --target js --release` to generate the browser executable.

## Safety model

- The root and every relative path are validated. Absolute paths, `..`, symbolic links, and internal state directories are rejected.
- The local server validates loopback hosts, same-origin requests, cross-site request metadata, and a random session token.
- Apply and undo operations verify file size, modification time, and SHA-256 again.
- Native `rename(..., replace=false)` prevents overwriting existing targets.
- Two-stage moves support swaps and rename cycles. The journal is updated with synchronous temporary writes and atomic replacement.
- A scan accepts at most 10,000 files. Hashing reads file contents, so very large folders can take time.
- Duplicate copies are quarantined for undo instead of being permanently deleted.
- Remove a stale `.filenest/lock` only after confirming that no FileNest process is running.

## Open source

FileNest is released under the [MIT License](LICENSE). See [Value Proof](docs/VALUE_PROOF.md) for necessity and validation evidence, [Provenance](docs/PROVENANCE.md) for dependency and ecosystem research, and [Architecture](docs/ARCHITECTURE.md) for the engineering design. Confirm the competition account namespace before publishing to Mooncakes.
