# Necessity and value

## A reproducibility problem, not another HTTP framework

MoonBit already has HTTP transports and web frameworks. Those projects help an application send or receive network traffic. MoonReplay addresses the next developer problem: preserving one concrete interaction so it can be inspected, simulated, replayed, and compared.

A webhook bug often arrives as “the callback failed.” The useful evidence is distributed across a provider dashboard, application logs, temporary headers, and the current server implementation. Reconstructing it manually is slow and often inaccurate. The request may contain a signature header, repeated query value, nested JSON field, or path identifier that was omitted from the report.

MoonReplay keeps the whole bounded exchange as one local artifact and turns it into a repeatable test input.

## Concrete workflows

### Webhook development

A developer points a payment, Git hosting, form, or automation callback at MoonReplay. The traffic view shows what arrived. A route can return the exact 2xx, 4xx, delay, header, or JSON body needed to exercise the sender. Sensitive values are masked before the exchange reaches disk.

### Frontend and mobile development

A UI can continue working before its backend endpoint is ready. Mock rules describe method and path conditions plus deterministic responses. Template variables let one rule serve `/users/{id}` or `/orders/{orderId}` without embedding application code.

### Failure reproduction

A captured request can be replayed against a repaired local service. MoonReplay compares the new response with the recorded response. JSON differences identify a field path such as `$.order.state`; text differences identify the first changed line.

### Regression fixtures

Teams can keep non-secret route definitions in Git and load them in local or CI environments. The same matcher and validator run on Native and JavaScript targets, so fixture behavior is deterministic and portable.

### Third-party integration debugging

When an integration changes behavior, cURL export gives a small reproducible case. The developer can share the sanitized command or route rather than sharing a database dump or an entire application environment.

## Why local operation matters

HTTP captures frequently contain bearer tokens, cookies, customer payloads, and internal URLs. Uploading every debugging request to a hosted inspector creates a second data destination. MoonReplay binds to loopback, persists locally, bounds history, and applies default redaction before saving.

This does not make arbitrary captured data safe to share. It does remove the need for a cloud account and gives the developer an inspectable policy boundary.

## Why a general tool is feasible here

MoonReplay does not attempt to migrate application state or understand business-specific versions. Its abstraction is the HTTP exchange, which already has stable, general parts: method, target, headers, body, response, and elapsed time. Mock matching and replay operate on those protocol-level values, while application-specific behavior remains in explicit route fixtures.

That boundary is small enough to test thoroughly and broad enough to support many applications.

## Evidence in the repository

The value claim is backed by executable behavior:

- a real MoonBit HTTP server captures arbitrary paths;
- a real MoonBit HTTP client replays requests;
- the matcher supports path parameters, metadata, and structured bodies;
- the redactor traverses nested JSON;
- the diff engine reports structural response changes;
- Native tests complete an HTTP replay round trip;
- the browser console exposes capture, route management, replay, cURL export, and diff results.

The project is therefore usable as a standalone developer tool while also publishing reusable protocol logic in its portable core.
