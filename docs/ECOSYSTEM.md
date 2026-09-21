# Selection and ecosystem comparison

MoonMigrate focuses on versioned changes to an application's on-disk layout.

## Adjacent MoonBit tools

- The official [`moon work`](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html) commands manage MoonBit workspace membership and dependency synchronization.
- [`moongrep`](https://mooncakes.io/docs/moonbit-community/moongrep) provides structural source search and linting.
- [`moonmodguard`](https://mooncakes.io/docs/Noverberrain/moonmodguard) audits module manifests and dependency policy.
- [`moonbit-notary`](https://mooncakes.io/docs/hcjbat/moonbit-notary) creates content evidence manifests and integrity reports.
- [`moon-ninja`](https://mooncakes.io/docs/Zcxssxx/moon-ninja) models build graphs and incremental execution.
- [`moon-data-contract`](https://mooncakes.io/docs/lyjttio/moon-data-contract) validates structured data contracts and compatibility.

These tools address workspaces, source analysis, supply-chain policy, integrity evidence, builds, or data schemas. MoonMigrate operates on application-owned files during a version transition and supplies reversible Native execution. The closest familiar category is database migration, applied to directories, configuration, caches, indexes, and resources.

## Why it belongs in the ecosystem

MoonBit's async filesystem package supplies low-level primitives such as read, write, rename, remove, and locks. An application upgrade still has to define version continuity, validate expected old state, prevent replacement, persist progress, store backups, and reverse completed work. MoonMigrate packages those repeated concerns into a tested core and CLI that other MoonBit applications can call.

The project is an original implementation. It depends on `moonbitlang/async` and uses no source code from the adjacent projects above.
