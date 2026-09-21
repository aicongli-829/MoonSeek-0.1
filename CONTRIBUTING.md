# Contributing

1. Install the latest stable MoonBit toolchain and the Native C toolchain for your platform.
2. Run the checks documented in `docs/TESTING.md` before committing.
3. Keep deterministic manifest validation in the root package and operating-system behavior in `native`.
4. Preserve the preview-before-apply rule and non-overwriting destination behavior.
5. Changes to execution or recovery must include a real temporary-directory test that applies and rolls back the affected operation.
6. Do not commit `_build`, `.mooncakes`, `.tools`, `.moonmigrate`, `.filenest`, `.private`, generated JavaScript, or application data.

Issues should include the MoonBit version, operating system, sanitized manifest, expected result, and actual result. Use synthetic files and omit private paths, configuration values, backups, journals, and credentials.

Code size is measured from tracked `.mbt` sources, but readability, behavior, and tests take priority. Empty lines, copied implementations, or generated source must not be added to increase the count.
