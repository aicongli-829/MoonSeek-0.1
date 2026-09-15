///|
async fn send_content(
  connection : @http.ServerConnection,
  status : Int,
  reason : String,
  content_type : String,
  content : String,
) -> Unit {
  connection.send_response(status, reason, extra_headers={
    "Content-Type": content_type,
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  })
  connection.write(content)
  connection.end_response()
}

///|
async fn send_json(
  connection : @http.ServerConnection,
  value : Json,
  status? : Int = 200,
) -> Unit {
  send_content(
    connection,
    status,
    if status == 200 {
      "OK"
    } else {
      "Bad Request"
    },
    "application/json; charset=utf-8",
    value.stringify(),
  )
}

///|
async fn serve_asset(
  connection : @http.ServerConnection,
  path : String,
) -> Unit {
  let (file, content_type) = match path {
    "/" => ("web/index.html", "text/html; charset=utf-8")
    "/style.css" => ("web/style.css", "text/css; charset=utf-8")
    "/app.js" =>
      (
        "_build/js/release/build/webui/webui.js", "text/javascript; charset=utf-8",
      )
    _ => {
      send_json(connection, { "error": "页面不存在" }, status=404)
      return
    }
  }
  if !@fs.exists(file) {
    send_json(
      connection,
      {
        "error": "前端尚未构建，请先运行 moon build --target js --release webui",
      },
      status=500,
    )
    return
  }
  send_content(connection, 200, "OK", content_type, read_text(file))
}

///|
/// Run the local-only HTTP application. It binds exclusively to loopback.
pub async fn serve(port : Int, initial_root? : String = "") -> Unit {
  let state = ApplicationState::new(initial_root, port)
  let server = @http.Server(
    @socket.Addr::parse("127.0.0.1:\{port}"),
    reuse_addr=true,
  )
  println("FileNest 已启动：http://127.0.0.1:\{port}")
  println("在浏览器中打开上面的地址。按 Ctrl+C 退出。")
  server.run_forever(allow_failure=true) <| ((request, body, connection) => {
    try {
      if request.meth == Get {
        if request.path == "/api/session" {
          let defaults = parse_document(
            @core.configuration_defaults_json("{}"),
            "默认设置",
          )
          send_json(connection, {
            "token": state.token,
            "initialRoot": state.initial_root,
            "defaultOptions": json_field(defaults, "defaultOptions"),
            "builtInTemplates": json_field(defaults, "builtInTemplates"),
          })
        } else {
          serve_asset(connection, request.path)
        }
        return
      }
      guard request.meth == Post else {
        send_json(
          connection,
          { "error": "不支持的请求方式" },
          status=405,
        )
        return
      }
      let token = request.headers
        .get(@http.CaseInsensitiveString("X-FileNest-Token"))
        .unwrap_or("")
      let host = request.headers
        .get(@http.CaseInsensitiveString("Host"))
        .unwrap_or("")
      let origin = request.headers
        .get(@http.CaseInsensitiveString("Origin"))
        .unwrap_or("")
      let fetch_site = request.headers
        .get(@http.CaseInsensitiveString("Sec-Fetch-Site"))
        .unwrap_or("")
      guard token == state.token else {
        fail("会话已失效，请刷新页面")
      }
      guard host == "127.0.0.1:" + port.to_string() else {
        fail("Host 不匹配")
      }
      guard origin == "" || origin == state.origin else {
        fail("只允许本地应用访问")
      }
      guard fetch_site != "cross-site" else { fail("拒绝跨站请求") }
      let source = body.read_all().text()
      guard source.length() <= 2 * 1024 * 1024 else {
        fail("请求内容过大")
      }
      let input = if source.trim() == "" {
        ({} : Json)
      } else {
        parse_document(source, "请求内容")
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
