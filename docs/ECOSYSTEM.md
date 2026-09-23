# Ecosystem fit

MoonSeek is a general local file search engine. Its unit of indexing is a user-selected filesystem root, and its query results are ranked files.

Nearby tool categories solve different problems:

| Category | Primary purpose | Difference from MoonSeek |
| --- | --- | --- |
| Recursive grep | Exact or regular-expression content scan | Reopens files for each query and usually ignores non-text filenames |
| File finders | Fast path or filename lookup | Usually do not provide ranked multilingual content search |
| Source analyzers | Syntax-aware code navigation | Target program structure rather than arbitrary personal files |
| Document converters | Parse or render one document | Can become future extractors, but do not provide a persistent cross-folder search index |
| Server search engines | Multi-user, distributed search | Require substantially more deployment and administration |

The closest Mooncakes packages found during project research were a Chinese tokenizer, a structural MoonBit source search tool, and document-conversion libraries. Those are useful adjacent building blocks or specialized applications. None provides MoonSeek's combination of all-file filename indexing, selected-root persistence, mixed CJK/English full-text search, incremental reuse, fuzzy filename ranking, filters, local UI, and index diagnostics.

MoonSeek avoids bundling or copying those projects. Its tokenizer, inverted index, query parser, ranker, filesystem repository, ignore matcher, server, and UI are implemented in this repository. See [PROVENANCE.md](PROVENANCE.md).
