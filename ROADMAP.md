# Roadmap

## 0.1 · Search core

- [x] All-file filename and path indexing.
- [x] Text and source content indexing.
- [x] Mixed English, numeric, and CJK tokenization.
- [x] Incremental reuse of unchanged documents.
- [x] Ranked search, fuzzy filenames, filters, facets, and suggestions.
- [x] Multiple roots and `.moonseekignore` support.
- [x] Native CLI, loopback web interface, and index diagnostics.

## 0.2 · Faster updates

- [ ] Filesystem watcher with debounced update batches.
- [ ] Deleted-file tombstones without a full root scan.
- [ ] Configurable indexing profiles per root.
- [ ] Search latency and index throughput benchmark suite.

## 0.3 · Rich content

- [ ] Pluggable content extractors for PDF and office documents.
- [ ] Optional image metadata and OCR adapters.
- [ ] Segmented binary index for collections beyond 100,000 files.
- [ ] Editor and launcher integrations using the portable JSON API.
