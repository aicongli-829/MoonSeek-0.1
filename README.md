# MoonReplay

**MoonReplay is a local HTTP capture, mock, replay, and response-diff workbench written in MoonBit.** It gives an application a disposable local endpoint, records what actually arrived, returns deterministic mock responses, and replays a captured request against a real service to explain what changed.

It is useful when developing webhook consumers, frontend applications, mobile clients, third-party integrations, callback handlers, and HTTP APIs. All history stays on the developer's machine, and common credentials are redacted before persistence.

## The problem

HTTP integration failures are difficult to reproduce from a screenshot or a log line. Developers often need the exact method, path, query parameters, headers, and body that reached an endpoint. They then rebuild the request manually, lose the original response, and compare a second result by eye.

MoonReplay turns that workflow into four repeatable steps:

1. point the caller at `http://127.0.0.1:4173/<any-path>`;
2. inspect the captured exchange in a local web interface;
3. add a deterministic mock rule or replay the request to a target URL;
4. inspect a structural response diff instead of comparing raw text manually.

## What it provides

- capture every local HTTP method, path, query, header, and bounded request body;
- redact authorization headers, cookies, API keys, tokens, passwords, and nested JSON secrets before writing history;
- match mock routes by method, exact/prefix/template/wildcard path, query, headers, and body;
- match JSON bodies exactly or as structural subsets;
- render response templates from path parameters, query values, headers, and JSON body fields;
- configure status, headers, body, and a bounded response delay;
- replay a captured request to an absolute HTTP or HTTPS URL;
- compare status, headers, JSON structure, arrays, or the first changed text line;
- filter history by method, status family, path, header, body text, tag, or sequence range;
- export any captured request as a reproducible cURL command;
- validate route files before saving them;
- operate through a Native CLI or a local MoonBit web interface.

## Quick start

Requirements: a current stable MoonBit toolchain and a Native C toolchain.

```text
moon update
moon run --target native cmd/moonreplay -- init
moon run --target native cmd/moonreplay -- serve
```

Open `http://127.0.0.1:4173`, then send a request:

```text
curl -i -X POST http://127.0.0.1:4173/hooks/orders/42 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer local-secret" \
  --data '{"event":"order.paid","token":"private-value"}'
```

The request appears in the traffic list. The stored copy contains `[REDACTED]` in place of the authorization value and JSON token.

## Add a mock route

Save this as `order-webhook.json`, or use the route editor in the web interface:

```json
{
  "id": "order-webhook",
  "name": "Order webhook",
  "enabled": true,
  "priority": 10,
  "match": {
    "methods": ["POST"],
    "path": "/hooks/orders/{orderId}",
    "pathMode": "template",
    "headers": [],
    "query": [],
    "body": {
      "mode": "json-subset",
      "value": "{\"event\":\"order.paid\"}"
    }
  },
  "response": {
    "status": 202,
    "headers": [
      { "name": "Content-Type", "value": "application/json" }
    ],
    "body": "{\"accepted\":true,\"orderId\":\"{{path.orderId}}\"}",
    "delayMs": 0
  }
}
```

```text
moon run --target native cmd/moonreplay -- routes add order-webhook.json
```

The same request now receives HTTP 202 with the captured `orderId` inserted into the response.

## Replay and compare

Use an exchange identifier shown by `history list`:

```text
moon run --target native cmd/moonreplay -- history list --method POST
moon run --target native cmd/moonreplay -- replay <exchange-id> http://localhost:3000/webhooks/orders/42
```

The result contains the live response and a field-level diff against the recorded response. Volatile headers such as `Date`, `Server`, `Connection`, and `Content-Length` are ignored by default.

## Architecture

```text
caller / webhook producer
           │
           ▼
MoonBit Native HTTP server ──► redaction ──► atomic local history
           │                                      │
           ├── route matcher ──► template response│
           │                                      ▼
           └────────────────────────────── local web console
                                                  │
captured request ──► HTTP replay client ──► response diff
```

The portable core contains normalization, matching, templating, redaction, validation, filtering, cURL export, and response comparison. It compiles for Native and JavaScript. Native adapters provide filesystem persistence, the HTTP server/client, and the CLI. The browser application is written in MoonBit with a narrow DOM/fetch FFI layer.

See [Architecture](docs/ARCHITECTURE.md) for data flow and trust boundaries.

## Scope boundary

MoonReplay does not index documents, rank text, perform semantic retrieval, or provide RAG. Its inputs and outputs are HTTP exchanges and deterministic mock rules. This keeps the project separate from MoonSearch, MoonRetrieve, and other local search engines.

It also does not attempt to replace a production reverse proxy or API gateway. Version 0.1 binds to loopback, limits request bodies, and is designed for local development and CI fixtures.

## Data and safety defaults

- the server binds to `127.0.0.1`;
- administrative writes require a random browser session token;
- browser requests validate `Host` and `Origin`;
- request bodies are limited to 1 MiB;
- response delays are limited to 30 seconds;
- history retention is bounded and defaults to 2,000 exchanges;
- persistence uses write, sync, and atomic rename;
- sensitive data is redacted before persistence;
- replay omits `Host`, `Content-Length`, and `Connection` from captured headers.

Review [Security](SECURITY.md) before replaying data to a shared or production endpoint.

## Quality status

- 26 portable core tests cover matching, templates, redaction, diffs, filters, validation, and cURL export.
- 10 Native integration tests cover atomic workspaces, route replacement, history retention, filtering, and a real HTTP replay round trip.
- JavaScript and Native builds run with warnings denied.
- The repository contains more than 4,000 lines of hand-written MoonBit source; generated output and dependencies are excluded.
- The current tree contains no MoonSeek search implementation; its earlier history is retained for repository transparency.

Run all checks:

```text
moon fmt --check
moon check --target js --deny-warn
moon test --target js --deny-warn
moon check --target native --deny-warn
moon test --target native --deny-warn
moon build cmd/moonreplay --target native --release
```

## Documentation

- [CLI reference](docs/CLI.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Necessity and value](docs/VALUE_PROOF.md)
- [MoonBit ecosystem contribution](docs/ECOSYSTEM.md)
- [Testing](docs/TESTING.md)
- [Source provenance](docs/PROVENANCE.md)
- [Roadmap](ROADMAP.md)

MoonReplay is released under the [MIT License](LICENSE).
