# Provenance and dependencies

MoonMigrate is an original versioned filesystem migration framework implemented in this repository with AI-assisted development. It does not copy source code from the adjacent tools listed in [ECOSYSTEM.md](ECOSYSTEM.md).

## Runtime dependencies

- The official MoonBit toolchain and `moonbitlang/core` provide compilation, JSON, strings, and collections.
- `moonbitlang/async` provides Native filesystem and environment primitives.

The primary CLI has no Node.js, npm, cloud service, database, or external runtime dependency.

## Project history

The repository began as FileNest, a local file organizer. Its safe paths, SHA-256 implementation, journals, two-stage moves, and rollback experiments became the foundation for MoonMigrate. The organizer remains a secondary regression and visual example; it is not the submitted product direction.

## Code-size policy

Source-size figures count tracked `.mbt` files only. They exclude dependencies, generated output, HTML/CSS, documents, examples, and configuration. Functional scope, readable implementation, and meaningful tests take priority over line count; generated or duplicated code is not used to inflate the project.

## Publication

- GitHub: <https://github.com/aicongli-829/MoonMigrate-v1.0>
- Mooncakes: not published yet.

The module name is `moonmigrate/core`. The final Mooncakes namespace will be confirmed before registry publication.
