///|
fn status_label(status : String) -> String {
  match status {
    "ready" => "准备整理"
    "conflict" => "名称冲突"
    "invalid" => "需要修正"
    "unchanged" => "无需改变"
    "excluded" => "已排除"
    _ => status
  }
}

///|
fn option(value : String, label : String, selected : String) -> String {
  "<option value=\"" +
  value +
  "\"" +
  (if value == selected { " selected" } else { "" }) +
  ">" +
  label +
  "</option>"
}

///|
fn render_rules() -> Unit {
  let html = StringBuilder()
  if state.rules.length() == 0 {
    html.write_string(
      "<p class=\"small muted\">尚未添加规则，将保留原文件名。</p>",
    )
  }
  for index, rule in state.rules {
    html.write_string(
      "<div class=\"rule-card\"><div class=\"rule-header\"><span class=\"rule-number\">",
    )
    html.write_string((index + 1).to_string())
    html.write_string("</span><select data-action=\"rule-kind\" data-index=\"")
    html.write_string(index.to_string())
    html.write_string("\">")
    for
      item in [
        ("prefix", "添加前缀"),
        ("suffix", "添加后缀"),
        ("replace", "文字替换"),
        ("remove", "移除文字"),
        ("spaces", "空格转下划线"),
        ("lower", "名称转小写"),
        ("upper", "名称转大写"),
        ("extension_lower", "扩展名转小写"),
        ("number", "添加编号"),
        ("number_suffix", "末尾编号"),
        ("regex", "正则替换"),
      ] {
      let (kind, label) = item
      html.write_string(option(kind, label, rule.kind))
    }
    html.write_string(
      "</select><div class=\"rule-controls\"><button data-action=\"rule-up\" data-index=\"",
    )
    html.write_string(index.to_string())
    html.write_string(
      "\">↑</button><button data-action=\"rule-down\" data-index=\"",
    )
    html.write_string(index.to_string())
    html.write_string(
      "\">↓</button><button data-action=\"rule-remove\" data-index=\"",
    )
    html.write_string(index.to_string())
    html.write_string("\">×</button></div></div>")
    if !["spaces", "lower", "upper", "extension_lower"].contains(rule.kind) {
      html.write_string("<input data-action=\"rule-value\" data-index=\"")
      html.write_string(index.to_string())
      html.write_string("\" value=\"")
      html.write_string(html_escape(rule.value))
      html.write_string("\" placeholder=\"规则内容\">")
    }
    if ["replace", "regex"].contains(rule.kind) {
      html.write_string("<input data-action=\"rule-replacement\" data-index=\"")
      html.write_string(index.to_string())
      html.write_string("\" value=\"")
      html.write_string(html_escape(rule.replacement))
      html.write_string("\" placeholder=\"替换为（可留空）\">")
    }
    html.write_string("</div>")
  }
  dom_html("rule-list", html.to_string())
}

///|
fn render_categories() -> Unit {
  let html = StringBuilder()
  for index, category in state.categories {
    html.write_string(
      "<div class=\"rule-card\"><select data-action=\"category-kind\" data-index=\"",
    )
    html.write_string(index.to_string())
    html.write_string("\">")
    html.write_string(option("extension", "扩展名匹配", category.kind))
    html.write_string(option("keyword", "文件名包含", category.kind))
    html.write_string(
      "</select><input data-action=\"category-value\" data-index=\"",
    )
    html.write_string(index.to_string())
    html.write_string("\" value=\"")
    html.write_string(html_escape(category.value))
    html.write_string(
      "\" placeholder=\"匹配内容，例如 pdf\"><input data-action=\"category-folder\" data-index=\"",
    )
    html.write_string(index.to_string())
    html.write_string("\" value=\"")
    html.write_string(html_escape(category.folder))
    html.write_string(
      "\" placeholder=\"目标文件夹\"><button data-action=\"category-remove\" data-index=\"",
    )
    html.write_string(index.to_string())
    html.write_string("\">删除</button></div>")
  }
  dom_html("category-list", html.to_string())
  dom_hidden("category-editor", dom_value("classify") != "custom")
}

///|
fn render_inventory() -> Unit {
  let inventory = state.inventory
  let files = ui_array(inventory, "files")
  let groups = ui_array(inventory, "duplicates")
  dom_text("stat-total", files.length().to_string())
  dom_text("stat-duplicates", groups.length().to_string())
  dom_text("duplicate-count", groups.length().to_string())
  let html = StringBuilder()
  for group_index, raw_group in groups {
    let paths = match raw_group {
      Array(items) => items
      _ => []
    }
    html.write_string("<article class=\"duplicate-card\"><h3>重复组 ")
    html.write_string((group_index + 1).to_string())
    html.write_string(" · ")
    html.write_string(paths.length().to_string())
    html.write_string(" 个相同文件</h3>")
    for path_value in paths {
      match path_value {
        String(path) => {
          let checked = state.quarantine.contains(path)
          html.write_string(
            "<label class=\"duplicate-row\"><input type=\"checkbox\" data-action=\"quarantine\" data-index=\"",
          )
          html.write_string(html_escape(path))
          html.write_string("\"")
          if checked {
            html.write_string(" checked")
          }
          html.write_string("> 隔离 <code>")
          html.write_string(html_escape(path))
          html.write_string("</code></label>")
        }
        _ => ()
      }
    }
    html.write_string("</article>")
  }
  if groups.length() == 0 {
    html.write_string(
      "<p class=\"placeholder\">没有发现内容相同的文件。</p>",
    )
  }
  dom_html("duplicate-list", html.to_string())
}

///|
fn render_preview() -> Unit {
  let rows = ui_array(state.preview, "rows")
  let summary = ui_field(state.preview, "summary")
  dom_text("row-count", "· " + rows.length().to_string() + " 项")
  dom_text("stat-ready", ui_scalar(summary, "ready", "0"))
  let conflict_count = ui_scalar(summary, "conflict", "0")
  dom_text("stat-conflict", conflict_count)
  let html = StringBuilder()
  for index, row in rows {
    let source = ui_text(row, "source", "")
    let target = ui_text(row, "target", "")
    let status = ui_text(row, "status", "")
    html.write_string(
      "<tr><td><input type=\"checkbox\" data-action=\"exclude\" data-index=\"",
    )
    html.write_string(html_escape(source))
    html.write_string("\"")
    if !state.excluded.contains(source) {
      html.write_string(" checked")
    }
    html.write_string("></td><td><strong>")
    html.write_string(html_escape(source))
    html.write_string("</strong></td><td>")
    html.write_string(html_escape(target))
    html.write_string("</td><td><span class=\"status ")
    html.write_string(status)
    html.write_string("\">")
    html.write_string(status_label(status))
    html.write_string("</span></td></tr>")
    ignore(index)
  }
  dom_html("file-rows", html.to_string())
  dom_hidden("empty-state", rows.length() > 0)
  dom_hidden("table-wrap", rows.length() == 0)
  dom_disabled("execute", rows.length() == 0)
  dom_disabled("export-csv", rows.length() == 0)
  dom_disabled("export-json", rows.length() == 0)
  dom_disabled("export-md", rows.length() == 0)
}

///|
fn render_history(records : Array[Json]) -> Unit {
  let html = StringBuilder()
  for record in records {
    let id = ui_text(record, "id", "")
    let status = ui_text(record, "status", "unknown")
    html.write_string("<article class=\"history-card\"><div><strong>")
    html.write_string(html_escape(id))
    html.write_string("</strong><p class=\"small muted\">状态：")
    html.write_string(html_escape(status))
    html.write_string(" · 操作 ")
    html.write_string(ui_array(record, "operations").length().to_string())
    html.write_string(" 项</p></div>")
    if status != "undone" && status != "unreadable" {
      html.write_string("<button data-action=\"undo\" data-index=\"")
      html.write_string(html_escape(id))
      html.write_string("\">撤销</button>")
    }
    html.write_string("</article>")
  }
  if records.length() == 0 {
    html.write_string("<p class=\"placeholder\">还没有操作记录。</p>")
  }
  dom_html("history-list", html.to_string())
}

///|
fn render_templates() -> Unit {
  let choices = StringBuilder()
  choices.write_string("<option value=\"\">选择一个模板…</option>")
  let cards = StringBuilder()
  for template in all_templates() {
    let name = ui_text(template, "name", "未命名")
    let description = ui_text(template, "description", "整理规则")
    choices.write_string(
      "<option value=\"" +
      html_escape(name) +
      "\">" +
      html_escape(name) +
      "</option>",
    )
    cards.write_string(
      "<article class=\"template-card\"><h3>" +
      html_escape(name) +
      "</h3><p>" +
      html_escape(description) +
      "</p>",
    )
    cards.write_string(
      "<button data-action=\"template-apply\" data-index=\"" +
      html_escape(name) +
      "\">应用模板</button>",
    )
    if state.custom_templates.any(item => ui_text(item, "name", "") == name) {
      cards.write_string(
        "<button class=\"text-button\" data-action=\"template-delete\" data-index=\"" +
        html_escape(name) +
        "\">删除</button>",
      )
    }
    cards.write_string("</article>")
  }
  dom_html("template-select", choices.to_string())
  dom_html("template-cards", cards.to_string())
}

///|
fn show_view(name : String) -> Unit {
  for view in ["organize", "duplicates", "history", "templates"] {
    dom_hidden("view-" + view, view != name)
  }
  let (title, description, breadcrumb) = match name {
    "duplicates" =>
      (
        "相同内容，只留需要的副本。", "按内容确认重复，选择副本移入可撤销隔离区。",
        "重复文件",
      )
    "history" =>
      (
        "每一次整理，都可以回看。", "事务日志记录每个移动步骤，支持安全撤销。",
        "操作历史",
      )
    "templates" =>
      (
        "常用规则，留给下一次。", "内置模板帮助你快速开始。",
        "规则模板",
      )
    _ =>
      (
        "让每个文件，各归其位。", "分类、改名、检查重复。从一份清晰的预览开始。",
        "分类与改名",
      )
  }
  dom_text("page-title", title)
  dom_text("page-description", description)
  dom_text("breadcrumb", breadcrumb)
  if name == "history" {
    refresh_history()
  }
}
