# Security Policy

## Supported version

Security fixes are applied to the latest commit on `main` while FileNest is in its pre-1.0 development phase.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub Security Advisories for this repository. Include:

- the affected command or browser workflow;
- a minimal reproduction using synthetic files and paths;
- the operating system and MoonBit version;
- the expected and observed behavior;
- whether any file was moved, renamed, exposed, or overwritten.

Do not attach private documents, real `.filenest` journals, access tokens, or sensitive absolute paths. Replace them with a minimal temporary directory that reproduces the issue.

## Security boundaries

FileNest is designed to operate inside a user-selected root directory. It rejects traversal, absolute plan paths, symbolic links, and its own state directories. Apply and undo operations recheck file fingerprints and never replace an existing destination.

The browser service binds to `127.0.0.1`, validates the request host and origin, requires a random session token for changes, and does not return file contents. FileNest quarantines duplicate copies for undo; it does not provide permanent deletion.

These controls reduce mistakes and local request forgery, but they do not replace operating-system permissions or backups. Run FileNest with the least privilege needed for the selected directory.
