# Security policy

Security fixes apply to the latest commit on `main` during pre-1.0 development.

MoonSeek reads only roots explicitly selected by the user. It does not modify indexed source files. The database is written atomically under the configured database path. Symbolic links, reserved state directories, version-control metadata, dependencies, and build output are skipped.

The optional web server binds only to `127.0.0.1`. It validates `Host` and `Origin`, requires a random session token for POST requests, limits request size, and serves assets with a restrictive content security policy.

The index contains filenames, absolute root paths, metadata, token counts, and short text excerpts. Treat it as private user data. Do not publish a real index in a bug report.

Use GitHub Security Advisories for private vulnerability reports. Include a minimal reproduction with synthetic files, the operating system, MoonBit version, expected behavior, and observed behavior. Remove personal paths, file contents, tokens, and the index database.
