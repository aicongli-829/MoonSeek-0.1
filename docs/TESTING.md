# Testing

## Automated checks

```text
moon fmt --check
moon check --target js --deny-warn
moon test --target js
moon check --target native --deny-warn
moon test --target native
moon build cmd/moonseek --target native --release
```

Core tests cover tokenization, query parsing, categories, byte ranges, fuzzy scoring, ranking, phrase and exclusion behavior, facets, suggestions, formatting, and malformed index detection.

Native tests create real temporary directories and cover filename and content indexing, binary metadata indexing, incremental reuse, combined filters, multiple roots, root removal, `.moonseekignore`, persisted diagnostics, and suggestions. Temporary data is removed after each test.

## Manual smoke test

Create a disposable folder containing a text file, a source file, and a small image. Then run:

```text
moon run --target native cmd/moonseek -- index add ./smoke
moon run --target native cmd/moonseek -- status
moon run --target native cmd/moonseek -- search "sample"
moon run --target native cmd/moonseek -- search "type:image"
moon run --target native cmd/moonseek -- doctor
moon run --target native cmd/moonseek -- serve
```

Index the folder a second time and confirm that unchanged files appear in the `reused` count. Open the printed local URL and verify keyboard focus, live search, filters, path copying, root removal, and status refresh.

## Reporting failures

Include the operating system, MoonBit version, command, sanitized directory layout, expected result, and actual JSON response. Do not attach the real `.moonseek/index.json` database when it contains private filenames or excerpts.
