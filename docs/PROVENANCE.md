# Source provenance

MoonReplay is an original MoonBit implementation created for the MoonBit open-source hackathon.

The repository does not vendor source from RequestBin, webhook.site, MockServer, WireMock, mitmproxy, or similar tools. Those products establish that capture, mock, and replay workflows are useful; MoonReplay's matcher, template engine, redactor, validator, history model, diff engine, persistence adapter, CLI, and web interface were implemented for this repository.

The project depends on the official `moonbitlang/async` package for HTTP, sockets, filesystem operations, and asynchronous execution. MoonBit core packages provide JSON, strings, and environment access.

Generated build output, downloaded dependencies, and local toolchains are excluded from source-line claims and version control.

The repository history contains earlier hackathon prototypes named FileNest, MoonMigrate, and MoonSeek. Their current-tree implementations have been removed. They remain visible in Git history to preserve authorship and project evolution rather than rewriting public history.

All current user-facing copy, documentation, identifiers, examples, and comments are in English so the repository can be reviewed and reused internationally.
