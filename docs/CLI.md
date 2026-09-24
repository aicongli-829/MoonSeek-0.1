# CLI reference

All examples use the repository checkout:

```text
moon run --target native cmd/moonreplay -- <command>
```

## State options

- `--workspace PATH` selects the route workspace. Default: `.moonreplay/workspace.json`.
- `--history PATH` selects captured history. Default: `.moonreplay/history.json`.

## Initialize

```text
moon run --target native cmd/moonreplay -- init
moon run --target native cmd/moonreplay -- init --force
```

`--force` explicitly replaces an existing workspace. Normal initialization refuses accidental replacement.

## Serve

```text
moon run --target native cmd/moonreplay -- serve
moon run --target native cmd/moonreplay -- serve --port 4180
```

The server binds to `127.0.0.1`. Any path outside ` /__moonreplay/` is a capture/mock endpoint.

## Routes

```text
moon run --target native cmd/moonreplay -- routes list
moon run --target native cmd/moonreplay -- routes add examples/order-webhook.json
moon run --target native cmd/moonreplay -- routes remove order-webhook
```

`routes add` validates the complete resulting workspace before replacing the current file. An invalid route leaves the healthy workspace intact.

## History

```text
moon run --target native cmd/moonreplay -- history list
moon run --target native cmd/moonreplay -- history list --method POST --status 5xx
moon run --target native cmd/moonreplay -- history list --path /hooks --tag failure
moon run --target native cmd/moonreplay -- history show <exchange-id>
moon run --target native cmd/moonreplay -- history clear
```

Status filters accept exact codes such as `404`, families such as `5xx`, and ranges such as `400-499` through the core API.

## Replay

```text
moon run --target native cmd/moonreplay -- replay <exchange-id> http://localhost:3000/webhooks
```

Replay sends the sanitized stored request to the explicit target. The output contains the new response and a structured diff.

## cURL export

```text
moon run --target native cmd/moonreplay -- curl <exchange-id>
moon run --target native cmd/moonreplay -- curl <exchange-id> --base-url http://localhost:3000
```

The generated command excludes captured `Host` and `Content-Length` headers.

## Validate

```text
moon run --target native cmd/moonreplay -- validate
```

The report includes error and warning counts, route count, and machine-readable issue codes.
