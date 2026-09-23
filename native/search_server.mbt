///|
priv struct SearchApplicationState {
  database : String
  token : String
  origin : String
}

///|
fn SearchApplicationState::new(
  database : String,
  port : Int,
) -> SearchApplicationState {
  {
    database,
    token: operation_id() + operation_id(),
    origin: "http://127.0.0.1:" + port.to_string(),
  }
}

///|
async fn SearchApplicationState::dispatch(
  self : SearchApplicationState,
  path : String,
  input : Json,
) -> Json {
  let source = match path {
    "/api/status" => search_status_json(self.database)
    "/api/search" =>
      run_search_json(
        self.database,
        json_text(input, "query", ""),
        limit=json_int64_or(input, "limit", 50L).to_int(),
      )
    "/api/suggest" =>
      suggest_from_index_json(
        self.database,
        json_text(input, "prefix", ""),
        limit=json_int64_or(input, "limit", 12L).to_int(),
      )
    "/api/doctor" => diagnose_search_index_json(self.database)
    "/api/index" =>
      rebuild_search_index_json(
        self.database,
        json_text(input, "root", ""),
        options_source=json_field(input, "options").stringify(),
      )
    "/api/root/remove" =>
      remove_search_root_json(self.database, json_text(input, "root", ""))
    _ => fail("endpoint does not exist")
  }
  parse_document(source, "API result")
}

///|
/// Serve MoonSeek only on the loopback interface. The browser never receives
/// permission to enumerate the filesystem directly.
pub async fn serve_search(database : String, port : Int) -> Unit {
  let state = SearchApplicationState::new(database, port)
  let server = @http.Server(
    @socket.Addr::parse("127.0.0.1:\{port}"),
    reuse_addr=true,
  )
  println("MoonSeek is ready at http://127.0.0.1:\{port}")
  println("Open the address in a browser. Press Ctrl+C to stop.")
  server.run_forever(allow_failure=true) <| ((request, body, connection) => {
    try {
      if request.meth == Get {
        if request.path == "/api/session" {
          let status = parse_document(
            search_status_json(state.database),
            "search status",
          )
          send_json(connection, {
            "token": state.token,
            "database": state.database,
            "status": status,
            "queryHelp": parse_document(
              @core.search_query_help_json(),
              "query help",
            ),
          })
        } else {
          serve_asset(connection, request.path)
        }
        return
      }
      guard request.meth == Post else {
        send_json(connection, { "error": "method not allowed" }, status=405)
        return
      }
      let token = request.headers
        .get(@http.CaseInsensitiveString("X-MoonSeek-Token"))
        .unwrap_or("")
      let host = request.headers
        .get(@http.CaseInsensitiveString("Host"))
        .unwrap_or("")
      let origin = request.headers
        .get(@http.CaseInsensitiveString("Origin"))
        .unwrap_or("")
      guard token == state.token else {
        fail("session expired; refresh the page")
      }
      guard host == "127.0.0.1:" + port.to_string() else {
        fail("host mismatch")
      }
      guard origin == "" || origin == state.origin else {
        fail("local access only")
      }
      let source = body.read_all().text()
      guard source.length() <= 1024 * 1024 else { fail("request is too large") }
      let input = if source.trim() == "" {
        ({} : Json)
      } else {
        parse_document(source, "request")
      }
      let result = state.dispatch(request.path, input)
      match json_field(result, "error") {
        String(_) => send_json(connection, result, status=400)
        _ => send_json(connection, result)
      }
    } catch {
      error => send_json(connection, { "error": error.to_string() }, status=400)
    }
  })
}
