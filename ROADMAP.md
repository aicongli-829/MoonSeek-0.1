# FileNest Roadmap

The roadmap prioritizes safe file operations and practical local workflows. Dates are intentionally omitted until each milestone has an owner and test plan.

## 0.2 · MoonBit runtime

- [x] Deterministic classification and batch rename planning.
- [x] Native recursive scan and SHA-256 duplicate detection.
- [x] Two-stage apply and undo transactions.
- [x] Local browser workspace generated from MoonBit.
- [x] Native CLI, snapshots, analysis, reports, and templates.
- [x] JavaScript and Native automated test targets.

## 0.3 · Everyday usability

- [ ] Show scan and hashing progress for large folders.
- [ ] Add Chinese and English switching in the browser workspace.
- [ ] Provide more built-in templates for photos, coursework, and scanned documents.
- [ ] Improve keyboard navigation and screen-reader labels.
- [ ] Add a recovery guide for interrupted transactions.

## 0.4 · Cross-platform confidence

- [ ] Run integration tests on Windows, Linux, and macOS in CI.
- [ ] Document platform-specific filename and timestamp behavior.
- [ ] Measure memory and scan time on large synthetic datasets.
- [ ] Add bounded hashing concurrency without changing deterministic output.

## 1.0 · Stable release

- [ ] Freeze the CLI and `.fnrules` compatibility contract.
- [ ] Publish signed release archives and checksums.
- [ ] Publish the reusable MoonBit module to Mooncakes.
- [ ] Complete security, accessibility, and recovery reviews.

## Contribution priorities

Issues that prevent data loss, incorrect planning, or reliable undo take priority. Performance work must include a repeatable benchmark, and new rename operations must include collision and Unicode tests.
