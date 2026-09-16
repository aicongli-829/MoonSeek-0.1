## Problem and result

Describe the concrete FileNest workflow that was incorrect, missing, or difficult, followed by the resulting behavior.

## Changes

- 

## Validation

List the commands and manual workflows used to verify the change. For file operations, use a disposable directory and include apply/undo coverage when relevant.

```text
moon fmt --check
moon check --target js
moon test --target js
moon check --target native
moon test --target native
```

## Safety review

- [ ] Plans remain deterministic for identical inputs.
- [ ] Existing destination files are never overwritten.
- [ ] New file operations are journaled and can be audited.
- [ ] Apply and undo revalidate affected files.
- [ ] Tests and examples use synthetic data without private paths.

Remove checks that do not apply and explain any intentional limitation.
