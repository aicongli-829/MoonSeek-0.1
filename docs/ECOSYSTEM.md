# MoonBit ecosystem contribution

MoonReplay contributes an end-user developer tool and a reusable protocol-testing core.

## Distinct role

HTTP libraries answer “how do I send or serve a request?” Web frameworks answer “how do I route a request to application code?” MoonReplay answers “what exact request arrived, how can I simulate its response, and what changed when I replayed it?”

It composes with HTTP packages rather than replacing them. A framework application can receive replayed traffic, and any HTTP client can call its mock endpoints.

MoonReplay is also separate from search and retrieval projects. It has no document scanner, inverted index, tokenizer, BM25 ranker, vector store, or RAG pipeline. History filters operate on bounded HTTP metadata and do not provide full-text search.

## Reusable MoonBit components

The portable package demonstrates and exposes:

- canonical HTTP request models represented as stable JSON;
- deterministic route precedence;
- exact, prefix, template, and wildcard path matching;
- header and query predicate evaluation;
- exact and subset JSON matching;
- response template interpolation;
- recursive redaction policies;
- semantic JSON response diffs;
- bounded history filtering and pagination;
- workspace validation with machine-readable diagnostics;
- cURL generation.

These algorithms contain no filesystem or socket access and compile on JavaScript as well as Native.

## Native MoonBit coverage

The Native adapter exercises areas valuable to MoonBit application authors:

- asynchronous HTTP server and client APIs;
- atomic local persistence;
- bounded state files;
- CLI parsing;
- loopback browser applications;
- cross-target tests with strict warning checks.

## Browser MoonBit coverage

The web console is an executable MoonBit package. JavaScript is limited to small FFI functions for DOM access, events, fetch, clipboard, and confirmation. Filtering, rendering decisions, request payload construction, and state handling remain in MoonBit.

## Candidate Mooncakes packages

The portable core can later be published independently from the application:

- `moonreplay/core`: models, matchers, templates, redaction, validation, and diffs;
- `moonreplay/native`: persistence, capture server, replay client, and CLI.

This split lets another MoonBit project embed deterministic HTTP fixtures without launching the full web console.
