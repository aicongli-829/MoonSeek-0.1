# Contributing

1. Install the current stable MoonBit toolchain and the Native C toolchain for your platform.
2. Read `docs/ARCHITECTURE.md` and run the checks in `docs/TESTING.md`.
3. Keep deterministic search logic in the root package and operating-system access in `native`.
4. Add focused tests for ranking, parsing, index-format, ignore-rule, or filesystem changes.
5. Use synthetic temporary files in tests and reports.
6. Do not commit `_build`, `.mooncakes`, `.tools`, `.moonseek`, generated JavaScript, or private user data.

Issues should include the MoonBit version, operating system, sanitized input, expected result, and actual result. Readability and verified behavior take priority over source size; generated, copied, or empty code must not be used to inflate the project.
