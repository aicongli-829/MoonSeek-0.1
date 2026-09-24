///|
fn ui_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn ui_text(value : Json, key : String, fallback : String) -> String {
  match ui_field(value, key) {
    String(text) => text
    Number(number, ..) => number.to_int().to_string()
    _ => fallback
  }
}

///|
fn ui_bool(value : Json, key : String, fallback : Bool) -> Bool {
  match ui_field(value, key) {
    true => true
    false => false
    _ => fallback
  }
}

///|
fn ui_array(value : Json, key : String) -> Array[Json] {
  match ui_field(value, key) {
    Array(items) => items
    _ => []
  }
}

///|
fn html_escape(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&#39;")
}

///|
fn show_message(message : String, error : Bool) -> Unit {
  dom_text("message", message)
  dom_class_toggle("message", "error", error)
  dom_hidden("message", false)
}

///|
fn clear_message() -> Unit {
  dom_hidden("message", true)
}

///|
fn response(source : String, callback : (Json) -> Unit) -> Unit {
  let document = @json.parse(source) catch {
    _ => {
      show_message("MoonReplay returned an unreadable response.", true)
      return
    }
  }
  match ui_field(document, "error") {
    String(message) => show_message(message, true)
    _ => callback(document)
  }
}

///|
fn status_class(status : String) -> String {
  let code = @string.parse_int(status) catch { _ => 0 }
  if code >= 200 && code < 300 {
    "ok"
  } else if code >= 400 {
    "bad"
  } else {
    "neutral"
  }
}

///|
fn render_history(document : Json) -> Unit {
  let items = ui_array(document, "items")
  let total = ui_text(document, "total", "0")
  dom_text(
    "history-count",
    total + (if total == "1" { " exchange" } else { " exchanges" }),
  )
  dom_text("stat-exchanges", total)
  let html = StringBuilder()
  for item in items {
    let id = ui_text(item, "id", "")
    let verb = ui_text(item, "method", "GET")
    let path = ui_text(item, "path", "/")
    let status = ui_text(item, "status", "0")
    html.write_string(
      "<button class=\"traffic-row\" data-action=\"open-exchange\" data-index=\"",
    )
    html.write_string(html_escape(id))
    html.write_string("\"><span class=\"verb verb-")
    html.write_string(html_escape(verb.to_lower()))
    html.write_string("\">")
    html.write_string(html_escape(verb))
    html.write_string("</span><span class=\"traffic-path\">")
    html.write_string(html_escape(path))
    html.write_string("</span><span class=\"status ")
    html.write_string(status_class(status))
    html.write_string("\">")
    html.write_string(html_escape(status))
    html.write_string("</span><span class=\"duration\">")
    html.write_string(html_escape(ui_text(item, "durationMs", "0")))
    html.write_string(" ms</span></button>")
  }
  if items.length() == 0 {
    html.write_string(
      "<div class=\"empty\"><strong>No requests captured</strong><span>Send an HTTP request to any path on this server.</span></div>",
    )
  }
  dom_html("traffic-list", html.to_string())
}

///|
fn render_headers(rows : Array[Json]) -> String {
  if rows.length() == 0 {
    return "<p class=\"muted\">No headers</p>"
  }
  let html = StringBuilder()
  html.write_string("<dl class=\"headers\">")
  for row in rows {
    html.write_string("<dt>")
    html.write_string(html_escape(ui_text(row, "name", "")))
    html.write_string("</dt><dd>")
    html.write_string(html_escape(ui_text(row, "value", "")))
    html.write_string("</dd>")
  }
  html.write_string("</dl>")
  html.to_string()
}

///|
fn render_exchange(document : Json) -> Unit {
  let exchange = ui_field(document, "exchange")
  let request = ui_field(exchange, "request")
  let response_value = ui_field(exchange, "response")
  let id = ui_text(exchange, "id", "")
  dom_set_value("selected-exchange", id)
  dom_hidden("exchange-empty", true)
  dom_hidden("exchange-detail", false)
  dom_text("detail-method", ui_text(request, "method", "GET"))
  dom_text(
    "detail-path",
    ui_text(request, "target", ui_text(request, "path", "/")),
  )
  dom_text("detail-status", ui_text(response_value, "status", "0"))
  dom_text("detail-mode", ui_text(exchange, "mode", "capture"))
  dom_text("detail-route", ui_text(exchange, "routeId", "unmatched"))
  dom_html("request-headers", render_headers(ui_array(request, "headers")))
  dom_text("request-body", ui_text(request, "body", ""))
  dom_html(
    "response-headers",
    render_headers(ui_array(response_value, "headers")),
  )
  dom_text("response-body", ui_text(response_value, "body", ""))
}

///|
fn render_routes(workspace : Json) -> Unit {
  let routes = ui_array(workspace, "routes")
  dom_text("stat-routes", routes.length().to_string())
  let html = StringBuilder()
  for route in routes {
    let id = ui_text(route, "id", "")
    let rule = ui_field(route, "match")
    let response_value = ui_field(route, "response")
    let methods = ui_array(rule, "methods").filter_map(value => {
      match value {
        String(text) => Some(text)
        _ => None
      }
    })
    html.write_string("<article class=\"route-row\"><div><strong>")
    html.write_string(html_escape(ui_text(route, "name", id)))
    html.write_string("</strong><code>")
    html.write_string(
      html_escape(methods.join(", ") + " " + ui_text(rule, "path", "/")),
    )
    html.write_string("</code></div><span class=\"status ok\">")
    html.write_string(html_escape(ui_text(response_value, "status", "200")))
    html.write_string("</span><button data-action=\"edit-route\" data-index=\"")
    html.write_string(html_escape(id))
    html.write_string(
      "\">Edit</button><button class=\"danger\" data-action=\"remove-route\" data-index=\"",
    )
    html.write_string(html_escape(id))
    html.write_string("\">Remove</button></article>")
  }
  if routes.length() == 0 {
    html.write_string(
      "<div class=\"empty compact\"><strong>No mock routes yet</strong><span>Add the sample route or paste your own JSON.</span></div>",
    )
  }
  dom_html("route-list", html.to_string())
}

///|
fn refresh_history() -> Unit {
  let verb = dom_value("method-filter")
  let status = dom_value("status-filter")
  let path = dom_value("path-filter").trim().to_owned()
  api_request(
    "/__moonreplay/api/history",
    (
      {
        "filter": {
          "methods": if verb == "" {
            []
          } else {
            [verb]
          },
          "statuses": if status == "" {
            []
          } else {
            [status]
          },
          "path": path,
          "pathMode": "contains",
        },
        "limit": 100,
      } : Json).stringify(),
    source => response(source, render_history),
  )
}

///|
fn refresh_session() -> Unit {
  api_request("/__moonreplay/api/session", "{}", source => {
    response(source, session => {
      set_api_token(ui_text(session, "token", ""))
      render_routes(ui_field(session, "workspace"))
      render_history(ui_field(session, "history"))
    })
  })
}

///|
fn open_exchange(id : String) -> Unit {
  api_request("/__moonreplay/api/exchange", ({ "id": id } : Json).stringify(), source => {
    response(source, render_exchange)
  })
}

///|
fn replay_selected() -> Unit {
  let id = dom_value("selected-exchange")
  let target = dom_value("replay-target").trim().to_owned()
  if id == "" || target == "" {
    show_message("Select an exchange and enter an absolute replay URL.", true)
    return
  }
  dom_disabled("replay-button", true)
  api_request(
    "/__moonreplay/api/replay",
    ({ "id": id, "targetUrl": target } : Json).stringify(),
    source => {
      dom_disabled("replay-button", false)
      response(source, result => {
        let difference = ui_field(result, "difference")
        let count = ui_text(difference, "differenceCount", "0")
        show_message(
          if ui_bool(difference, "equal", false) {
            "Replay completed: response is identical."
          } else {
            "Replay completed: " + count + " response differences found."
          },
          false,
        )
        dom_text("diff-output", difference.stringify(indent=2))
        dom_hidden("diff-panel", false)
      })
    },
  )
}

///|
fn copy_curl() -> Unit {
  let id = dom_value("selected-exchange")
  if id == "" {
    show_message("Select an exchange first.", true)
    return
  }
  api_request("/__moonreplay/api/curl", ({ "id": id } : Json).stringify(), source => {
    response(source, result => {
      copy_text(ui_text(result, "command", ""))
      show_message("cURL command copied.", false)
    })
  })
}

///|
fn save_route() -> Unit {
  let source = dom_value("route-json").trim().to_owned()
  let route = @json.parse(source) catch {
    _ => {
      show_message("Route JSON is invalid.", true)
      return
    }
  }
  api_request(
    "/__moonreplay/api/route/upsert",
    ({ "route": route } : Json).stringify(),
    result => {
      response(result, _ => {
        show_message("Mock route saved.", false)
        refresh_session()
      })
    },
  )
}

///|
fn sample_route_source() -> String {
  (
    {
      "id": "order-webhook",
      "name": "Order webhook",
      "enabled": true,
      "priority": 10,
      "match": {
        "methods": ["POST"],
        "path": "/hooks/orders/{orderId}",
        "pathMode": "template",
        "headers": [],
        "query": [],
        "body": { "mode": "any", "value": "" },
      },
      "response": {
        "status": 202,
        "headers": [{ "name": "Content-Type", "value": "application/json" }],
        "body": "{\"accepted\":true,\"orderId\":\"{{path.orderId}}\"}",
        "delayMs": 0,
      },
    } : Json).stringify(indent=2)
}

///|
fn initialize_events() -> Unit {
  bind_click("refresh-button", refresh_session)
  bind_click("filter-button", refresh_history)
  bind_click("replay-button", replay_selected)
  bind_click("curl-button", copy_curl)
  bind_click("save-route-button", save_route)
  bind_click("sample-route-button", () => {
    dom_set_value("route-json", sample_route_source())
  })
  bind_click("clear-button", () => {
    if browser_confirm("Clear all captured request history?") {
      api_request("/__moonreplay/api/history/clear", "{}", source => {
        response(source, _ => {
          show_message("Request history cleared.", false)
          refresh_history()
        })
      })
    }
  })
  bind_delegate("traffic-list", (action, id, _) => {
    if action == "open-exchange" {
      open_exchange(id)
    }
  })
  bind_delegate("route-list", (action, id, _) => {
    if action == "remove-route" && browser_confirm("Remove route '" + id + "'?") {
      api_request(
        "/__moonreplay/api/route/remove",
        ({ "id": id } : Json).stringify(),
        source => response(source, _ => refresh_session()),
      )
    } else if action == "edit-route" {
      show_message(
        "Copy the route JSON from the workspace file to edit it safely.", false,
      )
      dom_focus("route-json")
    }
  })
}

///|
fn main {
  initialize_events()
  dom_set_value("route-json", sample_route_source())
  clear_message()
  refresh_session()
}
