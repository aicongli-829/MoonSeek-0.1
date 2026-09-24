# Architecture

## Packages

### `moonreplay/core`

The root package is deterministic and portable. It owns request normalization, route matching, response templates, redaction, response comparison, history predicates, cURL export, and workspace validation.

Public boundary functions accept and return JSON strings. This makes the same core callable from Native code, the generated JavaScript module, test fixtures, and future integrations without duplicating models.

### `moonreplay/core/native`

The Native package owns side effects:

- atomic workspace and history files;
- the loopback HTTP capture/mock server;
- outbound replay requests;
- administrative API endpoints;
- CLI commands.

### `cmd/moonreplay`

The executable delegates to the Native CLI adapter. It contains no business rules.

### `webui`

The browser executable renders traffic, exchange details, routes, and response diffs. Its FFI surface contains only browser primitives.

## Request flow

1. The Native server accepts a request on `127.0.0.1`.
2. The body is rejected if it exceeds the configured hard limit.
3. The portable core normalizes method, target, path, query, and headers.
4. Enabled routes are evaluated. Priority wins first; match specificity breaks ties.
5. A matching route renders its response template. An unmatched request receives a diagnostic 404.
6. Request and response pass through the redaction policy.
7. The sanitized exchange is appended through an atomic history replacement.
8. The raw in-memory mock response is sent to the caller.

Redaction happens before persistence. The response sent to the caller is not changed by redaction.

## Replay flow

1. The user selects a sanitized stored exchange and supplies a target URL.
2. MoonReplay removes hop-by-hop and connection-specific captured headers.
3. The Native client sends the method, remaining headers, and body.
4. The client collects status, headers, body, and elapsed milliseconds.
5. The portable diff engine compares the live response with the recorded response.
6. The CLI or web console presents both the response and structured differences.

## Route precedence

Every candidate receives a match score. Explicit methods, literal path segments, body conditions, and metadata predicates increase specificity. Selection compares:

1. greater numeric `priority`;
2. greater specificity score;
3. earlier route order when both are equal.

This makes emergency overrides possible while keeping normal fixtures deterministic.

## Persistence

`workspace.json` stores settings and route fixtures. `history.json` stores a bounded exchange array and the next monotonic sequence. Writes use a unique temporary file, request full sync, and atomically replace the destination.

The current format version is `1`. Unknown workspace versions fail validation instead of being interpreted loosely.

## Trust boundaries

- Capture traffic is untrusted and size-bounded.
- Route files are untrusted and validated before replacement.
- Administrative POST endpoints require a random session token plus local `Host` and `Origin` checks.
- The server listens only on loopback.
- Replay targets are explicit user input. MoonReplay never replays automatically.
- Stored captures are sanitized, but users must still inspect data before sharing it.

## Deliberate limits

Version 0.1 supports HTTP/1.1 behavior exposed by the MoonBit async HTTP package. It is a local development tool, not a TLS terminator, transparent system proxy, tunnel service, traffic sniffer, or production gateway.
