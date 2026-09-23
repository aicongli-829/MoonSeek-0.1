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
      show_message("MoonSeek returned an unreadable response.", true)
      return
    }
  }
  match ui_field(document, "error") {
    String(message) => show_message(message, true)
    _ => callback(document)
  }
}

///|
fn render_status(status : Json) -> Unit {
  let statistics = ui_field(status, "statistics")
  let roots = ui_array(status, "roots")
  dom_text("stat-documents", ui_text(statistics, "documents", "0"))
  dom_text("stat-terms", ui_text(statistics, "terms", "0"))
  dom_text("stat-tokens", ui_text(statistics, "tokens", "0"))
  dom_text("stat-roots", roots.length().to_string())
  let html = StringBuilder()
  for root in roots {
    match root {
      String(path) => {
        html.write_string(
          "<article class=\"root-row\"><span class=\"root-icon\">⌁</span><code>",
        )
        html.write_string(html_escape(path))
        html.write_string(
          "</code><button data-action=\"remove-root\" data-index=\"",
        )
        html.write_string(html_escape(path))
        html.write_string(
          "\" title=\"Remove from index\">×</button></article>",
        )
      }
      _ => ()
    }
  }
  if roots.length() == 0 {
    html.write_string("<p class=\"empty-copy\">No folders indexed yet.</p>")
  }
  dom_html("root-list", html.to_string())
}

///|
fn render_results(document : Json) -> Unit {
  let results = ui_array(document, "results")
  let total = ui_text(document, "total", "0")
  dom_text(
    "result-count",
    total + (if total == "1" { " match" } else { " matches" }),
  )
  let html = StringBuilder()
  for result in results {
    let root = ui_text(result, "root", "")
    let path = ui_text(result, "path", "")
    let full = if root.has_suffix("\\") || root.has_suffix("/") {
      root + path
    } else if root.contains("\\") {
      root + "\\" + path.replace_all(old="/", new="\\")
    } else {
      root + "/" + path
    }
    html.write_string(
      "<article class=\"result-card\"><div class=\"file-badge\">",
    )
    let extension = ui_text(result, "extension", "FILE").to_upper()
    let badge = if extension == "" { "FILE" } else { extension }
    html.write_string(html_escape(badge))
    html.write_string("</div><div class=\"result-body\"><h2>")
    html.write_string(html_escape(ui_text(result, "name", path)))
    html.write_string("</h2><p class=\"result-path\">")
    html.write_string(html_escape(full))
    html.write_string("</p><p class=\"snippet\">")
    html.write_string(html_escape(ui_text(result, "snippet", "")))
    html.write_string("</p><div class=\"result-meta\"><span>score ")
    html.write_string(html_escape(ui_text(result, "score", "0")))
    html.write_string("</span><span>")
    html.write_string(html_escape(ui_text(result, "matchKind", "match")))
    html.write_string("</span><span>")
    html.write_string(html_escape(ui_text(result, "sizeLabel", "0 bytes")))
    html.write_string(
      "</span></div></div><button class=\"copy-button\" data-action=\"copy-path\" data-index=\"",
    )
    html.write_string(html_escape(full))
    html.write_string("\">Copy path</button></article>")
  }
  if results.length() == 0 {
    html.write_string(
      "<div class=\"empty-results\"><div>⌕</div><h2>No matching files</h2><p>Try fewer words or remove a filter.</p></div>",
    )
  }
  dom_html("results", html.to_string())
}

///|
fn refresh_status() -> Unit {
  api_request("/api/status", "{}", source => response(source, render_status))
}

///|
fn search_action() -> Unit {
  let query = dom_value("query").trim().to_owned()
  if query == "" {
    dom_html(
      "results", "<div class=\"empty-results\"><div>⌕</div><h2>Search everything you indexed</h2><p>Type a filename, phrase, or content keyword.</p></div>",
    )
    dom_text("result-count", "Ready")
    return
  }
  clear_message()
  dom_class_toggle("search-shell", "searching", true)
  api_request(
    "/api/search",
    ({ "query": query, "limit": 80 } : Json).stringify(),
    source => {
      if dom_value("query").trim().to_owned() != query {
        return
      }
      dom_class_toggle("search-shell", "searching", false)
      response(source, render_results)
    },
  )
}

///|
fn index_action() -> Unit {
  let root = dom_value("root").trim().to_owned()
  if root == "" {
    show_message("Paste a folder path first.", true)
    return
  }
  dom_disabled("index-button", true)
  dom_text("index-button", "Indexing…")
  clear_message()
  api_request(
    "/api/index",
    ({ "root": root, "options": {} } : Json).stringify(),
    source => {
      dom_disabled("index-button", false)
      dom_text("index-button", "Add folder")
      response(source, result => {
        let scan = ui_field(result, "scan")
        show_message(
          "Index updated: " +
          ui_text(scan, "indexed", "0") +
          " read, " +
          ui_text(scan, "reused", "0") +
          " unchanged.",
          false,
        )
        dom_set_value("root", "")
        refresh_status()
        dom_focus("query")
      })
    },
  )
}

///|
fn initialize_events() -> Unit {
  bind_search_input("query", search_action)
  bind_click("index-button", index_action)
  bind_click("refresh-button", refresh_status)
  bind_global_shortcuts("query")
  bind_delegate("results", (action, path, _) => {
    if action == "copy-path" {
      copy_text(path)
      show_message("Path copied to the clipboard.", false)
    }
  })
  bind_delegate("root-list", (action, root, _) => {
    if action == "remove-root" &&
      browser_confirm("Remove this folder from the index?") {
      api_request("/api/root/remove", ({ "root": root } : Json).stringify(), source => {
        response(source, _ => refresh_status())
      })
    }
  })
}

///|
fn main {
  initialize_events()
  api_request("/api/session", "{}", source => {
    response(source, session => {
      set_api_token(ui_text(session, "token", ""))
      render_status(ui_field(session, "status"))
      dom_focus("query")
    })
  })
}
