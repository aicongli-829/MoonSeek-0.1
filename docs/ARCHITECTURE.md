# Architecture

MoonSeek separates deterministic search logic from operating-system access.

## Portable core

The root `moonseek/core` package owns mixed-language tokenization, query parsing, file categories, size ranges, inverted-index construction, BM25-style ranking, filename fuzzy matching, snippets, facets, suggestions, and index diagnostics. Its public boundaries accept and return JSON so the same core can be called from Native, JavaScript, browser, editor, or future MoonBit applications.

The index stores a document table and a sorted term table. Each posting records content, filename, and path frequencies separately. Ranking weights filenames most strongly, then paths, then content. Document length normalization prevents long files from dominating. Equal scores use path order for deterministic output.

## Native adapter

`moonseek/core/native` owns filesystem scanning, metadata collection, ignore rules, atomic persistence, multiple-root updates, CLI dispatch, and the local HTTP service.

On an update, the scanner compares each path's size and modification value with the previous document table. Matching documents reuse persisted term counts without reopening file contents. Changed text files are retokenized. Non-text files still contribute filename and path tokens.

The database is written to a unique temporary file with full synchronization, then renamed over the previous index. A failed write leaves the previous complete index available.

## Local service

The service binds to loopback only. The initial session response supplies a random token. POST requests require that token and validate `Host` and `Origin`. Static assets use a restrictive content security policy. The browser receives search results and selected paths, but it cannot enumerate the filesystem directly.

## Limits

Format version 1 is a single JSON index intended for personal collections up to 100,000 files. Updates scan configured roots and reuse unchanged documents; a persistent filesystem watcher and segmented on-disk postings are planned for larger collections. Content extraction from binary office and PDF formats is outside version 0.1; those files remain searchable by filename and path.
