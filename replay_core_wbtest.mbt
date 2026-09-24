///|
fn test_json(source : String) -> Json raise {
  @json.parse(source) catch {
    _ => fail("expected JSON output")
  }
}

///|
fn sample_request(
  verb? : String = "POST",
  target? : String = "/hooks/order/42?dryRun=true",
  body? : String = "{\"customer\":{\"id\":7},\"state\":\"paid\"}",
) -> Json {
  {
    "id": "request-1",
    "receivedAt": "2026-09-24T08:00:00Z",
    "method": verb,
    "target": target,
    "headers": [
      { "name": "Content-Type", "value": "application/json" },
      { "name": "X-Tenant", "value": "north" },
      { "name": "Authorization", "value": "Bearer secret" },
    ],
    "body": body,
  }
}

///|
fn sample_route(
  path? : String = "/hooks/order/{orderId}",
  mode? : String = "template",
) -> Json {
  {
    "id": "route-order",
    "name": "Order webhook",
    "enabled": true,
    "priority": 10,
    "match": {
      "methods": ["POST"],
      "path": path,
      "pathMode": mode,
      "headers": [
        { "name": "x-tenant", "operator": "equals", "value": "north" },
      ],
      "query": [{ "name": "dryRun", "operator": "equals", "value": "true" }],
      "body": { "mode": "json-subset", "value": "{\"state\":\"paid\"}" },
    },
    "response": {
      "status": 202,
      "headers": [
        { "name": "Content-Type", "value": "application/json" },
        { "name": "X-Order", "value": "{{path.orderId}}" },
      ],
      "body": "{\"accepted\":true,\"id\":\"{{path.orderId}}\",\"customer\":\"{{body.customer.id}}\"}",
      "delayMs": 25,
    },
  }
}

///|
test "normalization separates path and query" {
  let request = normalize_request(sample_request())
  assert_eq(replay_text(request, "path", ""), "/hooks/order/42")
  assert_eq(replay_array(request, "query").length(), 1)
  assert_eq(query_values(request, "dryRun"), ["true"])
}

///|
test "normalization canonicalizes header names" {
  let request = normalize_request(sample_request())
  assert_eq(header_value(request, "CONTENT-TYPE"), Some("application/json"))
  assert_eq(header_value(request, "x-tenant"), Some("north"))
}

///|
test "percent decoder handles query spaces and hex" {
  assert_eq(percent_decode("hello+world", plus_as_space=true), "hello world")
  assert_eq(percent_decode("a%2Fb"), "a/b")
  assert_eq(percent_decode("bad%zz"), "bad%zz")
}

///|
test "path normalizer removes dot segments" {
  assert_eq(normalize_path("/api/./orders/../users"), "/api/users")
  assert_eq(normalize_path(""), "/")
}

///|
test "wildcard matcher supports star and question mark" {
  assert_true(wildcard_match("/api/*/events", "/api/order/events"))
  assert_true(wildcard_match("/v?/users", "/v1/users"))
  assert_false(wildcard_match("/api/*/events", "/other/events"))
}

///|
test "template path captures named segments" {
  let finding = match_template_path("/hooks/{kind}/{id}", "/hooks/order/42")
  assert_true(finding.matched)
  assert_eq(finding.variables["kind"], "order")
  assert_eq(finding.variables["id"], "42")
}

///|
test "template path reports a segment mismatch" {
  let finding = match_template_path("/hooks/{id}", "/hooks/order/42")
  assert_false(finding.matched)
  assert_true(finding.reasons.length() > 0)
}

///|
test "complete route matches a webhook request" {
  let finding = match_request(sample_route(), sample_request())
  assert_true(finding.matched)
  assert_eq(finding.variables["orderId"], "42")
  assert_true(finding.score > 0)
}

///|
test "route rejects the wrong HTTP method" {
  let finding = match_request(sample_route(), sample_request(verb="GET"))
  assert_false(finding.matched)
  assert_true(finding.reasons.any(reason => reason.contains("method")))
}

///|
test "route rejects a missing required header" {
  let request : Json = {
    "method": "POST",
    "target": "/hooks/order/42?dryRun=true",
    "headers": [],
    "body": "{\"state\":\"paid\"}",
  }
  let finding = match_request(sample_route(), request)
  assert_false(finding.matched)
  assert_true(finding.reasons.any(reason => reason.contains("header")))
}

///|
test "JSON subset matcher ignores additional request fields" {
  let expected = test_json("{\"state\":\"paid\"}")
  let actual = test_json("{\"state\":\"paid\",\"attempt\":2}")
  assert_true(json_contains(expected, actual))
  assert_false(json_contains(actual, expected))
}

///|
test "exact JSON body matching ignores object key order" {
  let route = sample_route()
  match replay_field(route, "match") {
    Object(rule) =>
      rule["body"] = {
        "mode": "json",
        "value": "{\"state\":\"paid\",\"customer\":{\"id\":7}}",
      }
    _ => ()
  }
  let finding = match_request(route, sample_request())
  assert_true(finding.matched)
}

///|
test "route selection favors priority before specificity" {
  let low = sample_route()
  let high : Json = {
    "id": "catch-all",
    "name": "Emergency response",
    "enabled": true,
    "priority": 50,
    "match": {
      "methods": [],
      "path": "/hooks",
      "pathMode": "prefix",
      "headers": [],
      "query": [],
      "body": { "mode": "any", "value": "" },
    },
    "response": { "status": 503, "headers": [], "body": "maintenance" },
  }
  let selected = select_route([low, high], sample_request())
  assert_eq(replay_text(replay_field(selected, "route"), "id", ""), "catch-all")
}

///|
test "route selection favors specificity at equal priority" {
  let exact = sample_route(path="/hooks/order/42", mode="exact")
  let prefix : Json = {
    "id": "prefix",
    "name": "Prefix",
    "enabled": true,
    "priority": 10,
    "match": {
      "methods": ["POST"],
      "path": "/hooks",
      "pathMode": "prefix",
      "headers": [],
      "query": [],
      "body": { "mode": "any" },
    },
    "response": { "status": 200, "headers": [], "body": "" },
  }
  let selected = select_route([prefix, exact], sample_request())
  assert_eq(
    replay_text(replay_field(selected, "route"), "id", ""),
    "route-order",
  )
}

///|
test "response templates render path query header and JSON body values" {
  let rendered = render_response(sample_route(), sample_request())
  assert_eq(replay_int(rendered, "status", 0), 202)
  assert_true(replay_text(rendered, "body", "").contains("\"id\":\"42\""))
  assert_true(replay_text(rendered, "body", "").contains("\"customer\":\"7\""))
  let headers = rows_to_string_map(replay_array(rendered, "headers"))
  assert_eq(headers["X-Order"], "42")
}

///|
test "unknown template variables render as empty strings" {
  assert_eq(
    render_template("before {{missing}} after", sample_request(), Map([])),
    "before  after",
  )
}

///|
test "redaction masks sensitive headers and nested JSON fields" {
  let input : Json = {
    "request": sample_request(
      body="{\"password\":\"open-sesame\",\"profile\":{\"token\":\"abc\"}}",
    ),
    "response": {
      "status": 200,
      "headers": [{ "name": "Set-Cookie", "value": "sid=secret" }],
      "body": "{}",
    },
    "policy": {},
  }
  let output = test_json(redact_exchange_json(input.stringify()))
  let request = replay_field(output, "request")
  assert_eq(header_value(request, "authorization"), Some("[REDACTED]"))
  assert_false(replay_text(request, "body", "").contains("open-sesame"))
  assert_false(replay_text(request, "body", "").contains("abc"))
}

///|
test "custom redaction policy adds header names" {
  let input : Json = {
    "request": sample_request(),
    "response": {},
    "policy": { "headers": ["x-tenant"], "replacement": "***" },
  }
  let output = test_json(redact_exchange_json(input.stringify()))
  assert_eq(
    header_value(replay_field(output, "request"), "x-tenant"),
    Some("***"),
  )
}

///|
test "JSON response diff reports nested value changes" {
  let input : Json = {
    "expected": {
      "status": 200,
      "headers": [{ "name": "Content-Type", "value": "application/json" }],
      "body": "{\"user\":{\"name\":\"Ada\",\"active\":true}}",
    },
    "actual": {
      "status": 200,
      "headers": [{ "name": "Content-Type", "value": "application/json" }],
      "body": "{\"user\":{\"name\":\"Ada\",\"active\":false}}",
    },
    "options": {},
  }
  let result = test_json(diff_responses_json(input.stringify()))
  assert_false(replay_bool(result, "equal", true))
  assert_eq(replay_text(result, "bodyMode", ""), "json")
  assert_true(
    replay_array(result, "differences").any(item => {
      replay_text(item, "path", "") == "$.user.active"
    }),
  )
}

///|
test "response diff ignores volatile headers by default" {
  let input : Json = {
    "expected": {
      "status": 204,
      "headers": [{ "name": "Date", "value": "yesterday" }],
      "body": "",
    },
    "actual": {
      "status": 204,
      "headers": [{ "name": "Date", "value": "today" }],
      "body": "",
    },
    "options": {},
  }
  let result = test_json(diff_responses_json(input.stringify()))
  assert_true(replay_bool(result, "equal", false))
}

///|
test "text response diff identifies the first changed line" {
  let input : Json = {
    "expected": { "status": 200, "headers": [], "body": "one\ntwo\nthree" },
    "actual": { "status": 200, "headers": [], "body": "one\nchanged\nthree" },
    "options": {},
  }
  let result = test_json(diff_responses_json(input.stringify()))
  assert_eq(replay_text(result, "bodyMode", ""), "text")
  assert_eq(
    replay_text(replay_array(result, "differences")[0], "path", ""),
    "body.line[2]",
  )
}

///|
fn sample_exchange(
  id : String,
  sequence : Int,
  verb : String,
  path : String,
  status : Int,
) -> Json {
  {
    "id": id,
    "sequence": sequence,
    "receivedAt": "2026-09-24T08:00:00Z",
    "request": { "method": verb, "target": path, "headers": [], "body": "" },
    "response": { "status": status, "headers": [], "body": "", "durationMs": 3 },
    "tags": if status >= 500 {
      ["failure"]
    } else {
      ["ok"]
    },
  }
}

///|
test "history filters methods status groups paths and tags" {
  let input : Json = {
    "exchanges": [
      sample_exchange("one", 1, "GET", "/health", 200),
      sample_exchange("two", 2, "POST", "/hooks/order", 500),
      sample_exchange("three", 3, "POST", "/hooks/user", 202),
    ],
    "filter": {
      "methods": ["POST"],
      "statuses": ["5xx"],
      "path": "/hooks",
      "pathMode": "prefix",
      "tags": ["failure"],
    },
    "limit": 20,
  }
  let result = test_json(filter_exchanges_json(input.stringify()))
  assert_eq(replay_int(result, "total", 0), 1)
  assert_eq(replay_text(replay_array(result, "items")[0], "id", ""), "two")
}

///|
test "history pagination is newest first" {
  let input : Json = {
    "exchanges": [
      sample_exchange("one", 1, "GET", "/one", 200),
      sample_exchange("two", 2, "GET", "/two", 200),
      sample_exchange("three", 3, "GET", "/three", 200),
    ],
    "filter": {},
    "offset": 1,
    "limit": 1,
  }
  let result = test_json(filter_exchanges_json(input.stringify()))
  assert_eq(replay_text(replay_array(result, "items")[0], "id", ""), "two")
  assert_true(replay_bool(result, "hasMore", false))
}

///|
test "workspace validator accepts a complete route" {
  let workspace : Json = { "formatVersion": 1, "routes": [sample_route()] }
  let report = test_json(validate_workspace_json(workspace.stringify()))
  assert_true(replay_bool(report, "valid", false))
  assert_eq(replay_int(report, "errors", -1), 0)
}

///|
test "workspace validator finds duplicate ids and invalid responses" {
  let first = sample_route()
  let second = sample_route(path="broken", mode="unknown")
  match replay_field(second, "response") {
    Object(fields) => fields["status"] = 999
    _ => ()
  }
  let workspace : Json = { "formatVersion": 1, "routes": [first, second] }
  let report = test_json(validate_workspace_json(workspace.stringify()))
  assert_false(replay_bool(report, "valid", true))
  assert_true(replay_int(report, "errors", 0) >= 3)
}

///|
test "curl export preserves method headers body and target" {
  let input : Json = {
    "baseUrl": "http://localhost:8080",
    "request": sample_request(),
  }
  let result = test_json(export_curl_json(input.stringify()))
  let command = replay_text(result, "command", "")
  assert_true(command.contains("-X POST"))
  assert_true(command.contains("x-tenant: north"))
  assert_true(command.contains("/hooks/order/42?dryRun=true"))
}
