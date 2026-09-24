///|
priv struct ReplayApplicationState {
  workspace : String
  history : String
  token : String
  origin : String
}

///|
fn ReplayApplicationState::new(
  workspace : String,
  history : String,
  port : Int,
) -> ReplayApplicationState {
  {
    workspace,
    history,
    token: operation_id() + operation_id(),
    origin: "http://127.0.0.1:" + port.to_string(),
  }
}

///|
fn method_name(value : @http.RequestMethod) -> String {
  match value {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
  }
}

///|
fn incoming_headers(request : @http.Request) -> Array[Json] {
  let rows : Array[Json] = []
  for name, value in request.headers {
    rows.push({ "name": name.to_string(), "value": value })
  }
  rows
}

///|
fn response_reason(status : Int) -> String {
  match status {
    200 => "OK"
    201 => "Created"
    202 => "Accepted"
    204 => "No Content"
    301 => "Moved Permanently"
    302 => "Found"
    304 => "Not Modified"
    400 => "Bad Request"
    401 => "Unauthorized"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    409 => "Conflict"
    410 => "Gone"
    422 => "Unprocessable Content"
    429 => "Too Many Requests"
    500 => "Internal Server Error"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    _ => "MoonReplay Response"
  }
}

///|
fn rendered_headers(response : Json) -> @http.Headers {
  let headers : @http.Headers = Map([])
  for row in json_array(response, "headers") {
    let name = json_text(row, "name", "").trim().to_owned()
    if name != "" &&
      !["content-length", "connection", "transfer-encoding"].contains(
        name.to_lower(),
      ) {
      headers[@http.CaseInsensitiveString(name)] = json_text(row, "value", "")
    }
  }
  headers
}

///|
async fn send_mock_response(
  connection : @http.ServerConnection,
  response : Json,
) -> Unit {
  let delay = json_int64_or(response, "delayMs", 0L).to_int().max(0).min(30000)
  if delay > 0 {
    @async.sleep(delay)
  }
  let status = json_int64_or(response, "status", 200L).to_int()
  let headers = rendered_headers(response)
  let content_type = headers
    .get(@http.CaseInsensitiveString("content-type"))
    .unwrap_or("text/plain; charset=utf-8")
  send_content(
    connection,
    status,
    response_reason(status),
    content_type,
    json_text(response, "body", ""),
    extra=headers,
  )
}

///|
async fn ReplayApplicationState::session(self : ReplayApplicationState) -> Json {
  let workspace = load_workspace(self.workspace)
  let history = parse_document(
    list_exchanges_json(self.history, filter_source="{\"limit\":50}"),
    "history",
  )
  {
    "token": self.token,
    "workspacePath": self.workspace,
    "historyPath": self.history,
    "workspace": workspace,
    "history": history,
  }
}

///|
async fn ReplayApplicationState::admin_dispatch(
  self : ReplayApplicationState,
  path : String,
  input : Json,
) -> Json {
  let source = match path {
    "/__moonreplay/api/history" =>
      list_exchanges_json(self.history, filter_source=input.stringify())
    "/__moonreplay/api/exchange" =>
      get_exchange_json(self.history, json_text(input, "id", ""))
    "/__moonreplay/api/history/clear" => clear_history_json(self.history)
    "/__moonreplay/api/route/upsert" =>
      upsert_route_json(self.workspace, json_field(input, "route").stringify())
    "/__moonreplay/api/route/remove" =>
      remove_route_json(self.workspace, json_text(input, "id", ""))
    "/__moonreplay/api/replay" =>
      replay_exchange_json(
        self.history,
        json_text(input, "id", ""),
        json_text(input, "targetUrl", ""),
      )
    "/__moonreplay/api/curl" => {
      let loaded = parse_document(
        get_exchange_json(self.history, json_text(input, "id", "")),
        "exchange",
      )
      @core.export_curl_json(
        (
          {
            "baseUrl": json_text(input, "baseUrl", self.origin),
            "request": json_field(json_field(loaded, "exchange"), "request"),
          } : Json).stringify(),
      )
    }
    _ => fail("admin endpoint does not exist")
  }
  let result = parse_document(source, "admin result")
  match json_field(result, "error") {
    String(message) => fail(message)
    _ => result
  }
}

///|
async fn ReplayApplicationState::capture(
  self : ReplayApplicationState,
  request : @http.Request,
  body : String,
) -> (Json, Json) {
  let request_id = operation_id()
  let captured : Json = {
    "id": request_id,
    "receivedAt": @env.now().to_string(),
    "method": method_name(request.meth),
    "target": request.path,
    "headers": incoming_headers(request).to_json(),
    "body": body,
  }
  let workspace = load_workspace(self.workspace)
  let selection = parse_document(
    @core.select_route_json(
      ({ "routes": json_field(workspace, "routes"), "request": captured } : Json).stringify(),
    ),
    "route selection",
  )
  let matched = json_bool(selection, "matched", false)
  let route = json_field(selection, "route")
  let response = if matched {
    parse_document(
      @core.render_response_json(
        ({ "route": route, "request": captured } : Json).stringify(),
      ),
      "mock response",
    )
  } else {
    (
      {
        "status": 404,
        "headers": [{ "name": "Content-Type", "value": "application/json" }],
        "body": (
          {
            "error": "no MoonReplay route matched this request",
            "requestId": request_id,
          } : Json).stringify(),
        "delayMs": 0,
      } : Json)
  }
  let raw_exchange : Json = {
    "id": request_id,
    "receivedAt": @env.now().to_string(),
    "mode": if matched {
      "mock"
    } else {
      "capture"
    },
    "routeId": json_text(route, "id", ""),
    "request": captured,
    "response": response,
    "tags": [],
  }
  let policy = json_field(json_field(workspace, "settings"), "redaction")
  let redacted = parse_document(
    @core.redact_exchange_json(
      (
        {
          "request": json_field(raw_exchange, "request"),
          "response": json_field(raw_exchange, "response"),
          "policy": policy,
        } : Json).stringify(),
    ),
    "redacted exchange",
  )
  let stored : Json = {
    "id": request_id,
    "receivedAt": json_text(raw_exchange, "receivedAt", ""),
    "mode": json_text(raw_exchange, "mode", ""),
    "routeId": json_text(raw_exchange, "routeId", ""),
    "request": json_field(redacted, "request"),
    "response": json_field(redacted, "response"),
    "tags": [],
  }
  let history_limit = json_int64_or(
      json_field(workspace, "settings"),
      "historyLimit",
      2000L,
    )
    .to_int()
    .max(1)
    .min(100000)
  ignore(append_exchange(self.history, stored, limit=history_limit))
  (response, stored)
}

///|
fn valid_admin_request(
  state : ReplayApplicationState,
  request : @http.Request,
  port : Int,
) -> Bool {
  let token = request.headers
    .get(@http.CaseInsensitiveString("X-MoonReplay-Token"))
    .unwrap_or("")
  let host = request.headers
    .get(@http.CaseInsensitiveString("Host"))
    .unwrap_or("")
  let origin = request.headers
    .get(@http.CaseInsensitiveString("Origin"))
    .unwrap_or("")
  token == state.token &&
  (
    host == "127.0.0.1:" + port.to_string() ||
    host == "localhost:" + port.to_string()
  ) &&
  (
    origin == "" ||
    origin == state.origin ||
    origin == "http://localhost:" + port.to_string()
  )
}

///|
pub async fn serve_replay(
  workspace : String,
  history : String,
  port : Int,
) -> Unit {
  if !@fs.exists(workspace) {
    let initialized = parse_document(
      initialize_workspace_json(workspace),
      "workspace initialization",
    )
    match json_field(initialized, "error") {
      String(message) => fail(message)
      _ => ()
    }
  }
  let state = ReplayApplicationState::new(workspace, history, port)
  let server = @http.Server(
    @socket.Addr::parse("127.0.0.1:\{port}"),
    reuse_addr=true,
  )
  println("MoonReplay is ready at http://127.0.0.1:\{port}")
  println("Send requests to any path, or open the address in a browser.")
  println("Press Ctrl+C to stop.")
  server.run_forever(allow_failure=true) <| ((request, body, connection) => {
    try {
      if request.meth == Get && request.path == "/__moonreplay/api/session" {
        send_json(connection, state.session())
        return
      }
      if request.meth == Get &&
        (
          request.path == "/" ||
          request.path == "/style.css" ||
          request.path == "/app.js"
        ) {
        serve_asset(connection, request.path)
        return
      }
      let content = body.read_all().text()
      guard content.length() <= 1024 * 1024 else {
        send_json(
          connection,
          { "error": "request body exceeds 1 MiB" },
          status=413,
        )
        return
      }
      if request.path.has_prefix("/__moonreplay/api/") {
        guard request.meth == Post else {
          send_json(connection, { "error": "method not allowed" }, status=405)
          return
        }
        guard valid_admin_request(state, request, port) else {
          send_json(
            connection,
            { "error": "invalid local session" },
            status=403,
          )
          return
        }
        let input = if content.trim() == "" {
          ({} : Json)
        } else {
          parse_document(content, "admin request")
        }
        send_json(connection, state.admin_dispatch(request.path, input))
        return
      }
      let (response, _) = state.capture(request, content)
      send_mock_response(connection, response)
    } catch {
      error => send_json(connection, { "error": error.to_string() }, status=500)
    }
  })
}
