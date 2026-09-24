# Testing

MoonReplay uses strict cross-target checks and behavior-oriented tests.

## Full verification

```text
moon fmt --check
moon check --target js --deny-warn
moon test --target js --deny-warn
moon check --target native --deny-warn
moon test --target native --deny-warn
moon build cmd/moonreplay --target native --release
```

## Portable core coverage

The 26 core tests cover:

- target, path, query, and header normalization;
- percent decoding and dot-segment handling;
- wildcard and template paths;
- method, header, query, text-body, exact-JSON, and JSON-subset matching;
- priority and specificity route selection;
- path and JSON-body response templates;
- default and custom sensitive-data redaction;
- nested JSON, text, status, and header diffs;
- volatile-header defaults;
- history predicates, order, and pagination;
- workspace diagnostics;
- cURL generation.

## Native integration coverage

The 10 Native tests cover:

- workspace initialization and explicit replacement;
- create/replace route semantics;
- rejection of invalid routes without damaging healthy state;
- route removal;
- monotonic history sequences;
- bounded retention;
- persisted history filtering;
- lookup and clear operations;
- an in-process HTTP server/client round trip with method, header, body, status, and response header assertions.

Temporary directories are removed on both success and failure. Network tests bind to an ephemeral loopback port and do not access the public internet.

## CI

GitHub Actions installs the official toolchain, updates Mooncakes dependencies, performs strict JavaScript and Native checks, runs both test suites, builds the release executable, and verifies at least 4,000 tracked lines of hand-written MoonBit source.
