# Source provenance

MoonSeek is an original local search engine implemented in this repository with AI-assisted development. It does not copy source code from adjacent Mooncakes projects or desktop search applications.

The implementation consists of hand-written MoonBit for tokenization, query parsing, filters, file classification, index construction, ranking, fuzzy matching, snippets, facets, suggestions, diagnostics, ignore rules, Native filesystem access, atomic persistence, CLI and HTTP handling, and browser UI rendering. HTML and CSS provide the web shell. Generated build output and downloaded dependencies are excluded from version control and source-size reporting.

The repository previously explored local file organization and filesystem migration concepts. Those implementation files, commands, examples, and product documentation were removed when the project direction changed. Git history is retained for transparency; the current submitted product is MoonSeek.

MoonSeek uses the official `moonbitlang/async` package for filesystem, HTTP, socket, and I/O primitives. Dependency versions are declared in `moon.mod` and resolved through Mooncakes.
