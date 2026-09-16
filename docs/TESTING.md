# Testing and Troubleshooting

FileNest has a deterministic core, a Native filesystem layer, and a MoonBit-generated browser application. Validate the layer you changed, then run the complete matrix before merging.

## Complete check

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

The JavaScript target runs core tests. The Native target also covers SHA-256, timestamp conversion, real directory scanning, duplicate confirmation, journaled moves, and undo.

## Manual smoke test

Create a disposable directory containing two identical text files and one different image or text file. Never use irreplaceable data for a development smoke test.

```sh
moon run --target native cmd/filenest -- scan "path/to/smoke"
moon run --target native cmd/filenest -- preview "path/to/smoke" --config examples/downloads.json
moon run --target native cmd/filenest -- apply "path/to/smoke" --config examples/downloads.json --yes
moon run --target native cmd/filenest -- history "path/to/smoke"
moon run --target native cmd/filenest -- undo "path/to/smoke" BATCH-ID --yes
```

Confirm that preview and apply produce the same destinations, no pre-existing target changes, history records every move, and undo restores all source paths.

## Browser smoke test

```sh
moon build webui --target js --release
moon run --target native cmd/filenest -- serve --root "path/to/smoke"
```

Open `http://127.0.0.1:4173`, scan the disposable folder, inspect the preview, visit duplicate files, history, and templates, then verify that the browser console contains no errors. Apply is optional when the same transaction has already been tested through the CLI.

## Common failures

### Registry dependency not found

Run `moon update`. A fresh MoonBit installation may not yet have a current Mooncakes registry index, so CI performs this before dependency resolution.

### Native compiler is unavailable

Install the platform C toolchain. On Windows, use Visual Studio Build Tools with the C++ workload. On Linux or macOS, install the system compiler supported by the MoonBit toolchain.

### Browser page loads without behavior

Rebuild `webui` with the JS release target. The server reads `_build/js/release/build/webui/webui.js`; generated JavaScript is intentionally absent from Git.

### A stale operation lock remains

First confirm that no FileNest process is running for that root. Inspect `.filenest/history` before manually removing `.filenest/lock`. Never remove an active lock to force two simultaneous transactions.

### Apply reports that a file changed

Rescan and preview again. FileNest rejects execution when size, modification time, or SHA-256 differs from the approved inventory.

## Reporting failures

Include the operating system, MoonBit version, command, synthetic directory layout, rule file, and the smallest relevant output. Do not upload personal files, access tokens, full home-directory paths, or real transaction journals.
