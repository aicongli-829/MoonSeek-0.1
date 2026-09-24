# Security

## Supported version

Security fixes target the latest `main` branch until the first tagged release.

## Local trust model

MoonReplay is a local developer tool. The server binds to `127.0.0.1`. Administrative writes require a random session token and validate browser `Host` and `Origin` values.

Capture endpoints intentionally accept untrusted HTTP input. Bodies are bounded to 1 MiB. Mock delays are bounded to 30 seconds. History retention is bounded.

## Sensitive data

Default redaction covers authorization headers, proxy authorization, cookies, common API-key headers, token fields, passwords, client secrets, and payment-card field names. Custom names can be added in workspace settings.

Redaction is a defense against common accidental persistence. It cannot recognize every business-specific secret. Inspect captured data before committing, sharing, or attaching it to an issue.

Never commit `.moonreplay/history.json`. The repository ignore rules exclude local MoonReplay state.

## Replay safety

Replay only occurs after an explicit CLI or web-console action. A replay can trigger real side effects at its target. Use development or staging endpoints unless you intentionally want the production operation.

Stored requests are sanitized. Authentication values removed during capture are not recreated during replay.

## Reporting

Open a private GitHub security advisory for vulnerabilities. Include affected commit, operating system, reproduction steps, and impact. Do not include live credentials or unredacted request captures.
