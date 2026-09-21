# Security policy

## Supported version

Security fixes apply to the latest commit on `main` during pre-1.0 development.

## Migration safeguards

MoonMigrate restricts every manifest path to one selected root. It rejects traversal, absolute paths, symbolic links, reserved state directories, and replacement of existing move or copy targets. Optional SHA-256 preconditions bind operations to known old content.

Apply records action metadata before mutation and stores backups for changed files. Journals deliberately omit `write`, `find`, and replacement text so configuration secrets are not copied into history. Backups and quarantined files remain under `.moonmigrate` until rollback or an operator-defined retention step; protect this directory as application data.

These controls reduce accidental damage and ambiguous partial upgrades. They do not replace operating-system permissions or independent backups, and the current release does not claim database-grade atomicity across arbitrary power failures.

## Reporting a vulnerability

Use GitHub Security Advisories for private reports. Include:

- affected command and manifest operation;
- a minimal reproduction using synthetic files;
- operating system and MoonBit version;
- expected and observed behavior;
- whether any file was moved, replaced, exposed, or left partially migrated.

Do not attach real application data, `.moonmigrate` backups or journals, access tokens, private configuration values, or sensitive absolute paths.
