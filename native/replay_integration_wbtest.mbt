///|
fn integration_json(source : String) -> Json raise {
  @json.parse(source) catch {
    _ => fail("expected JSON output")
  }
}

///|
fn integration_route(id : String, status? : Int = 200) -> Json {
  {
    "id": id,
    "name": "Integration route " + id,
    "enabled": true,
    "priority": 0,
    "match": {
      "methods": ["POST"],
      "path": "/hooks/{id}",
      "pathMode": "template",
      "headers": [],
      "query": [],
      "body": { "mode": "any", "value": "" },
    },
    "response": {
      "status": status,
      "headers": [{ "name": "Content-Type", "value": "application/json" }],
      "body": "{\"ok\":true,\"id\":\"{{path.id}}\"}",
      "delayMs": 0,
    },
  }
}

///|
fn integration_exchange(id : String, sequence? : Int = 0) -> Json {
  {
    "id": id,
    "receivedAt": "2026-09-24T09:00:00Z",
    "mode": "mock",
    "routeId": "route-one",
    "request": {
      "id": id,
      "method": "POST",
      "target": "/hooks/42",
      "headers": [{ "name": "content-type", "value": "application/json" }],
      "body": "{\"event\":\"paid\"}",
    },
    "response": {
      "status": 202,
      "headers": [{ "name": "content-type", "value": "application/json" }],
      "body": "{\"accepted\":true}",
      "durationMs": sequence.to_string(),
    },
    "tags": ["test"],
  }
}

///|
async test "workspace initializes and validates on disk" {
  let root = @fs.tmpdir(prefix="moonreplay-workspace-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let workspace = root + "/state/workspace.json"
  let result = integration_json(initialize_workspace_json(workspace))
  assert_eq(json_bool(result, "created", false), true)
  assert_true(@fs.exists(workspace))
  let status = integration_json(workspace_status_json(workspace))
  assert_eq(json_int64_or(status, "routeCount", -1L), 0L)
  assert_eq(json_bool(json_field(status, "validation"), "valid", false), true)
  @fs.rmdir(root, recursive=true)
}

///|
async test "workspace initialization refuses accidental replacement" {
  let root = @fs.tmpdir(prefix="moonreplay-init-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let workspace = root + "/workspace.json"
  ignore(initialize_workspace_json(workspace))
  let second = integration_json(initialize_workspace_json(workspace))
  match json_field(second, "error") {
    String(message) => assert_true(message.contains("already exists"))
    _ => fail("second initialization should fail")
  }
  let replaced = integration_json(
    initialize_workspace_json(workspace, force=true),
  )
  assert_eq(json_bool(replaced, "created", false), true)
  @fs.rmdir(root, recursive=true)
}

///|
async test "route upsert creates and replaces by stable id" {
  let root = @fs.tmpdir(prefix="moonreplay-routes-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let workspace = root + "/workspace.json"
  ignore(initialize_workspace_json(workspace))
  let created = integration_json(
    upsert_route_json(
      workspace,
      integration_route("route-one", status=200).stringify(),
    ),
  )
  assert_eq(json_bool(created, "created", false), true)
  assert_eq(json_int64_or(created, "routeCount", -1L), 1L)
  let replaced = integration_json(
    upsert_route_json(
      workspace,
      integration_route("route-one", status=202).stringify(),
    ),
  )
  assert_eq(json_bool(replaced, "created", true), false)
  assert_eq(json_int64_or(replaced, "routeCount", -1L), 1L)
  let listed = integration_json(list_routes_json(workspace))
  let response = json_field(json_array(listed, "routes")[0], "response")
  assert_eq(json_int64_or(response, "status", 0L), 202L)
  @fs.rmdir(root, recursive=true)
}

///|
async test "invalid route never replaces a healthy workspace" {
  let root = @fs.tmpdir(prefix="moonreplay-invalid-route-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let workspace = root + "/workspace.json"
  ignore(initialize_workspace_json(workspace))
  ignore(upsert_route_json(workspace, integration_route("healthy").stringify()))
  let invalid : Json = {
    "id": "broken",
    "name": "Broken",
    "enabled": true,
    "match": {
      "methods": ["POST"],
      "path": "missing-slash",
      "pathMode": "exact",
    },
    "response": { "status": 999, "headers": [], "body": "" },
  }
  let result = integration_json(
    upsert_route_json(workspace, invalid.stringify()),
  )
  match json_field(result, "error") {
    String(_) => ()
    _ => fail("invalid route should be rejected")
  }
  let listed = integration_json(list_routes_json(workspace))
  assert_eq(json_array(listed, "routes").length(), 1)
  assert_eq(json_text(json_array(listed, "routes")[0], "id", ""), "healthy")
  @fs.rmdir(root, recursive=true)
}

///|
async test "route removal updates the persisted workspace" {
  let root = @fs.tmpdir(prefix="moonreplay-remove-route-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let workspace = root + "/workspace.json"
  ignore(initialize_workspace_json(workspace))
  ignore(upsert_route_json(workspace, integration_route("one").stringify()))
  ignore(upsert_route_json(workspace, integration_route("two").stringify()))
  let removed = integration_json(remove_route_json(workspace, "one"))
  assert_eq(json_text(removed, "removed", ""), "one")
  assert_eq(json_int64_or(removed, "routeCount", -1L), 1L)
  let listed = integration_json(list_routes_json(workspace))
  assert_eq(json_text(json_array(listed, "routes")[0], "id", ""), "two")
  @fs.rmdir(root, recursive=true)
}

///|
async test "history assigns monotonic sequences and returns newest first" {
  let root = @fs.tmpdir(prefix="moonreplay-history-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let history = root + "/history.json"
  let first = append_exchange(history, integration_exchange("one"))
  let second = append_exchange(history, integration_exchange("two"))
  assert_eq(json_int64_or(first, "sequence", 0L), 1L)
  assert_eq(json_int64_or(second, "sequence", 0L), 2L)
  let listed = integration_json(list_exchanges_json(history))
  assert_eq(json_int64_or(listed, "total", 0L), 2L)
  assert_eq(json_text(json_array(listed, "items")[0], "id", ""), "two")
  @fs.rmdir(root, recursive=true)
}

///|
async test "history retention drops the oldest exchanges" {
  let root = @fs.tmpdir(prefix="moonreplay-retention-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let history = root + "/history.json"
  for index = 1; index <= 5; index = index + 1 {
    ignore(
      append_exchange(
        history,
        integration_exchange("event-" + index.to_string()),
        limit=3,
      ),
    )
  }
  let listed = integration_json(list_exchanges_json(history))
  assert_eq(json_int64_or(listed, "total", 0L), 3L)
  let items = json_array(listed, "items")
  assert_eq(json_text(items[0], "id", ""), "event-5")
  assert_eq(json_text(items[2], "id", ""), "event-3")
  @fs.rmdir(root, recursive=true)
}

///|
async test "history filters persisted exchanges" {
  let root = @fs.tmpdir(prefix="moonreplay-history-filter-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let history = root + "/history.json"
  ignore(append_exchange(history, integration_exchange("first")))
  let changed = integration_exchange("failure")
  match json_field(changed, "response") {
    Object(fields) => fields["status"] = 503
    _ => ()
  }
  ignore(append_exchange(history, changed))
  let result = integration_json(
    list_exchanges_json(
      history,
      filter_source=(
        { "filter": { "methods": ["POST"], "statuses": ["5xx"] }, "limit": 10 } :
        Json).stringify(),
    ),
  )
  assert_eq(json_int64_or(result, "total", 0L), 1L)
  assert_eq(json_text(json_array(result, "items")[0], "id", ""), "failure")
  @fs.rmdir(root, recursive=true)
}

///|
async test "history lookup and clear are explicit operations" {
  let root = @fs.tmpdir(prefix="moonreplay-clear-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let history = root + "/history.json"
  ignore(append_exchange(history, integration_exchange("kept")))
  let loaded = integration_json(get_exchange_json(history, "kept"))
  assert_eq(json_text(json_field(loaded, "exchange"), "id", ""), "kept")
  let cleared = integration_json(clear_history_json(history))
  assert_eq(json_int64_or(cleared, "removed", 0L), 1L)
  let listed = integration_json(list_exchanges_json(history))
  assert_eq(json_int64_or(listed, "total", -1L), 0L)
  @fs.rmdir(root, recursive=true)
}

///|
async test "native HTTP replay sends method headers and body" {
  @async.with_task_group() <| group => {
    let server = @http.Server(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_addr=true,
    )
    let port = server.addr.port()
    group.add_defer(() => server.close())
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(allow_failure=true) <| ((request, body, connection) => {
        let content = body.read_all().text()
        let marker = request.headers
          .get(@http.CaseInsensitiveString("x-test"))
          .unwrap_or("missing")
        connection.send_response(201, "Created", extra_headers={
          "Content-Type": "application/json",
          "X-Echo": marker,
        })
        connection.write(
          ({ "method": method_name(request.meth), "body": content } : Json).stringify(),
        )
        connection.end_response()
      })
    }
    @async.sleep(20)
    let request : Json = {
      "method": "POST",
      "headers": [{ "name": "X-Test", "value": "roundtrip" }],
      "body": "payload",
    }
    let response = replay_request(
      request,
      target_url="http://127.0.0.1:\{port}/receive",
    )
    assert_eq(json_int64_or(response, "status", 0L), 201L)
    assert_true(json_text(response, "body", "").contains("payload"))
    assert_true(
      json_array(response, "headers").any(row => {
        json_text(row, "name", "").to_lower() == "x-echo" &&
        json_text(row, "value", "") == "roundtrip"
      }),
    )
  }
}
