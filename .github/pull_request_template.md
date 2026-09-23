## Problem and result

Describe the concrete MoonSeek indexing or search workflow that was incorrect, missing, or difficult, followed by the resulting behavior.

## Changes

- <!-- List the main implementation changes. -->

## Validation

List the commands and manual workflows used to verify the change. Use a disposable directory for filesystem tests.

```text
moon fmt --check
moon check --target native --deny-warn
moon test --target native
moon build cmd/moonseek --target native --release
```

## Review checklist

- [ ] Search output remains deterministic for identical inputs.
- [ ] Indexed source files are never modified.
- [ ] Index format changes are versioned and diagnosed.
- [ ] Native changes have temporary-directory coverage.
- [ ] Tests and examples use synthetic data without private paths or content.

Remove checks that do not apply and explain any intentional limitation.
