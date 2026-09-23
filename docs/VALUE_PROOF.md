# Necessity and value

## The recurring problem

People remember a phrase, a topic, or part of a filename more often than they remember an exact folder. Their files are spread across notes, source repositories, exported chat records, logs, course material, removable drives, and archived projects. Opening folders one by one wastes time, while a fresh recursive content search reopens the same files for every query.

The problem appears in common workflows:

1. A developer searches several repositories for an error message, then narrows results to logs or MoonBit source.
2. A student searches mixed English and Chinese notes without remembering the course folder or exact filename.
3. A designer remembers “summer holiday” but not whether the image uses spaces, underscores, or a slightly different spelling.
4. A support engineer searches old text exports and configuration snapshots while excluding generated files and dependency trees.
5. A user attaches an external drive whose contents are not covered by the operating system's usual index.

These workflows need the same small set of primitives: choose trusted roots, index once, update cheaply, search names and contents together, rank useful matches first, and keep the data local.

## What MoonSeek contributes

MoonSeek implements those primitives as reusable MoonBit packages rather than a thin wrapper over an external search executable.

- The tokenizer handles ASCII words, numbers, CJK characters, and adjacent CJK pairs.
- The index builder creates deterministic document and posting tables.
- The search engine uses term rarity, document-length normalization, and separate filename, path, and content weights.
- Filename fuzzy matching recovers prefixes, subsequences, word initials, and short edit errors.
- The query language composes text with extension, category, path, root, size, modification, phrase, and exclusion filters.
- The Native adapter indexes every filename, reads recognized text safely, respects ignore rules, and reuses unchanged documents.
- The same core compiles for Native and JavaScript and exposes stable JSON functions for other MoonBit programs.

## Why it belongs in the MoonBit ecosystem

MoonBit has filesystem primitives and language-specific code tools, but a general local search engine also needs tokenization, persisted postings, ranking, query filters, incremental reuse, diagnostics, and a usable interface. MoonSeek provides this middle layer in MoonBit. Other projects can import the portable core for documentation search, editor search, offline knowledge bases, static-site search, or application-specific asset catalogs.

The project also exercises MoonBit in a practical desktop workload: recursive Native I/O, deterministic data processing, HTTP, JavaScript interop, multilingual text, and real filesystem integration tests.

## Verifiable scope

Version 0.1 makes bounded claims. It supports up to 100,000 regular files in selected roots and stores one local JSON index. Binary office files, PDFs, images, audio, and archives are searchable by filename and path; their internal content is not extracted. The project does not claim to replace enterprise search or an operating-system shell. Its value is a transparent, portable, local search core and an immediately usable personal tool.
