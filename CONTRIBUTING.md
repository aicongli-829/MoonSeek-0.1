# Contributing

MoonReplay accepts focused bug fixes, tests, fixture improvements, documentation, and features aligned with local HTTP reproducibility.

## Development

```text
moon update
moon fmt
moon check --target js --deny-warn
moon test --target js --deny-warn
moon check --target native --deny-warn
moon test --target native --deny-warn
```

Keep protocol rules in the portable root package. Put filesystem and network side effects in `native`. Keep JavaScript FFI small and browser-specific.

## Pull requests

- explain the concrete HTTP workflow being improved;
- add a meaningful test for matcher, redaction, persistence, or replay behavior;
- preserve deterministic route selection;
- avoid logging unredacted credentials;
- update the CLI or architecture documentation when behavior changes.

Run formatting and both target test suites before submitting.
