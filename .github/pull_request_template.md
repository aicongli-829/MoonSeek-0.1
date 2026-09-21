## Problem and result

Describe the concrete MoonMigrate workflow that was incorrect, missing, or difficult, followed by the resulting behavior.

## Changes

- <!-- List the main implementation changes. -->

## Validation

List the commands and manual workflows used to verify the change. For file operations, use a disposable directory and include apply/undo coverage when relevant.

```text
moon fmt --check
moon check --target native
moon test --target native
moon build cmd/moonmigrate --target native --release
```

## Safety review

- [ ] Plans remain deterministic for identical inputs.
- [ ] Existing destination files are never overwritten.
- [ ] New file operations are journaled and can be audited.
- [ ] Apply and rollback revalidate affected files.
- [ ] Tests and examples use synthetic data without private paths.

Remove checks that do not apply and explain any intentional limitation.
