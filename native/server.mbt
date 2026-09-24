///|
async fn send_content(
  connection : @http.ServerConnection,
  status : Int,
  reason : String,
  content_type : String,
  content : String,
  extra? : @http.Headers = Map([]),
) -> Unit {
  let headers : @http.Headers = {
    "Content-Type": content_type,
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  }
  for name, value in extra {
    headers[name] = value
  }
  connection.send_response(status, reason, extra_headers=headers)
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
      send_json(connection, { "error": "page not found" }, status=404)
      return
    }
  }
  guard @fs.exists(file) else {
    send_json(
      connection,
      {
        "error": "web UI is not built; run moon build --target js --release webui",
      },
      status=500,
    )
    return
  }
  send_content(connection, 200, "OK", content_type, read_text(file))
}
