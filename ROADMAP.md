# Roadmap

## 0.1 — hackathon release

- local request capture;
- deterministic mock routes;
- request and response redaction;
- bounded atomic history;
- replay to explicit HTTP/HTTPS targets;
- structural response comparison;
- cURL export;
- Native CLI and local MoonBit web console;
- strict Native and JavaScript CI.

## 0.2

- import and export HTTP Archive (`.har`) fixtures;
- optional JSON Schema body assertions;
- route groups and reusable response fragments;
- configurable diff ignore paths;
- streaming event updates in the web console;
- fixture-oriented CI command with process exit codes.

## 0.3

- OpenAPI example-to-route generation;
- record-forward mode with an explicit upstream allowlist;
- request sequence assertions;
- latency and failure profiles;
- published `moonreplay/core` and `moonreplay/native` Mooncakes packages.

Production proxying, TLS interception, system-wide packet capture, and public tunnel hosting are outside the intended scope.
