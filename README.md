# MoonSeek

**MoonSeek is a fast, local filename and full-text search engine written in MoonBit.** It builds a reusable index once, updates unchanged files incrementally, and returns ranked results through a Native CLI or a loopback-only web interface.

MoonSeek is intended for the everyday gap between opening folders manually and deploying a server search stack. A developer can search source trees and logs, a student can search mixed Chinese and English notes, and any desktop user can find a file by a partial or slightly mistyped name. Every regular file is searchable by name. Supported text and source formats are also searchable by content.

## Why this project is useful

Operating-system search can be slow or inconsistent when a location is not indexed, when content indexing is disabled, or when a user searches removable drives and project folders. Recursive command-line tools are excellent for exact searches, but they reopen files on every query and usually cover either names or contents.

MoonSeek keeps a compact local inverted index. Repeated searches read that index instead of walking the filesystem again. Its scope is concrete:

- locate files across several chosen folders from one search box;
- search filenames for every file type, including images and archives;
- search contents of common text, data, web, script, and source formats;
- tokenize English, numbers, and CJK text without a runtime dictionary;
- rank filename matches ahead of path and content matches;
- tolerate filename prefixes, subsequences, and short spelling errors;
- filter by extension, category, path, root, file size, or modification value;
- reuse unchanged documents during the next index update;
- keep all indexed data and HTTP traffic on the local machine.

The [necessity and value note](docs/VALUE_PROOF.md) gives concrete workflows and explains the MoonBit ecosystem contribution.

## Quick start

Requirements: the current stable MoonBit toolchain and a Native C toolchain.

```text
moon update
moon run --target native cmd/moonseek -- index add "C:\Users\me\Documents"
moon run --target native cmd/moonseek -- search "project report"
moon run --target native cmd/moonseek -- serve
```

Open `http://127.0.0.1:4173` after starting the server. The default database is `.moonseek/index.json`. Use `--database PATH` with any command to place it elsewhere.

Build a standalone release executable:

```text
moon build cmd/moonseek --target native --release
```

## Search language

```text
moonbit search                 words in filenames, paths, or indexed content
"quick start"                 exact phrase boost
report -draft                 exclude a term
ext:md,mbt                    extension filter
type:image                    semantic category filter
path:docs                     relative-path filter
root:projects                 indexed-root filter
size:<1mb                     size comparison
size:10kb..5mb                size range
size:large                    named size bucket
```

Examples can combine freely:

```text
moon run --target native cmd/moonseek -- search "error code" ext:log -debug
moon run --target native cmd/moonseek -- search "holiday type:image size:>1mb"
moon run --target native cmd/moonseek -- search "MoonBit path:docs"
```

See the complete [CLI reference](docs/CLI.md).

## Index behavior

MoonSeek indexes names and metadata for every regular file. It reads content only for known text formats and only up to the configured content-size limit, which defaults to 4 MiB per file. It skips version-control metadata, dependency trees, build output, its own database, and symbolic links.

Create a `.moonseekignore` file in an indexed root to add patterns:

```gitignore
# Skip generated output
generated/
*.min.js

# Keep one diagnostic log
*.log
!important.log
```

Patterns support `*`, `?`, `**`, anchored `/paths`, directory-only trailing slashes, and later `!` exceptions.

## Architecture

```text
MoonBit core                 Native adapter                 Local web app
tokenizer                    filesystem scanner             MoonBit UI
query parser          <----  incremental repository  <----  token-protected API
inverted index               CLI and HTTP server            HTML and CSS shell
ranking and fuzzy match      atomic index writes            keyboard-first search
```

The portable core has no filesystem access. Native code scans selected roots and writes the index atomically. The HTTP server binds only to `127.0.0.1`, validates the `Host` and `Origin` headers, and requires a random session token for POST requests.

## Quality status

- Native and JavaScript targets compile with warnings denied.
- Tests cover tokenization, ranking, fuzzy search, filters, ignore rules, incremental reuse, multiple roots, suggestions, and index validation.
- The repository contains more than 4,000 lines of hand-written MoonBit source; generated output and dependencies are excluded.
- The index format is versioned and includes a `doctor` command for structural validation.

Run the full checks:

```text
moon fmt --check
moon check --target js --deny-warn
moon test --target js
moon check --target native --deny-warn
moon test --target native
moon build cmd/moonseek --target native --release
```

## Project documents

- [Architecture](docs/ARCHITECTURE.md)
- [CLI reference](docs/CLI.md)
- [Necessity and value](docs/VALUE_PROOF.md)
- [MoonBit ecosystem fit](docs/ECOSYSTEM.md)
- [Testing](docs/TESTING.md)
- [Source provenance](docs/PROVENANCE.md)
- [Roadmap](ROADMAP.md)

MoonSeek is released under the [MIT License](LICENSE).
