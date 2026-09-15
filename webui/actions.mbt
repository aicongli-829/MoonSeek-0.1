///|
fn scan_action() -> Unit {
  let root = dom_value("root").trim().to_owned()
  if root == "" {
    show_message("请输入工作文件夹完整路径", true)
    return
  }
  clear_message()
  dom_disabled("scan", true)
  dom_text("scan", "扫描中…")
  api_request(
    "/api/scan",
    ({ "root": root, "options": current_options() } : Json).stringify(),
    source => {
      dom_disabled("scan", false)
      dom_text("scan", "扫描文件夹 →")
      response(source, result => {
        state.root = ui_text(result, "root", root)
        state.inventory = ui_field(result, "inventory")
        state.preview = Json::null()
        state.excluded = []
        state.quarantine = []
        render_inventory()
        refresh_templates()
        dom_disabled("preview", false)
        show_message(
          "扫描完成。现在可以调整规则并生成预览。", false,
        )
        preview_action()
      })
    },
  )
}

///|
fn preview_action() -> Unit {
  if !(state.inventory is Object(_)) {
    show_message("请先扫描文件夹", true)
    return
  }
  api_request(
    "/api/preview",
    ({ "options": current_options() } : Json).stringify(),
    source => {
      response(source, result => {
        state.preview = result
        render_preview()
        show_message(
          "预览已更新；执行前请检查目标位置和冲突。", false,
        )
      })
    },
  )
}

///|
fn execute_action() -> Unit {
  let id = ui_text(state.preview, "id", "")
  if id == "" {
    show_message("请先生成预览", true)
    return
  }
  if !browser_confirm(
      "确认执行当前整理计划？完成后可在操作历史中撤销。",
    ) {
    return
  }
  dom_disabled("execute", true)
  api_request(
    "/api/execute",
    ({ "planId": id, "confirm": true } : Json).stringify(),
    source => {
      response(source, result => {
        show_message(
          "整理完成，批次：" + ui_text(result, "id", ""),
          false,
        )
        state.preview = Json::null()
        dom_html("file-rows", "")
        dom_hidden("table-wrap", true)
        dom_hidden("empty-state", false)
        dom_disabled("execute", true)
      })
    },
  )
}

///|
fn export_action(format : String) -> Unit {
  let id = ui_text(state.preview, "id", "")
  if id == "" {
    show_message("请先生成预览", true)
    return
  }
  api_request(
    "/api/export",
    ({ "planId": id, "format": format } : Json).stringify(),
    source => {
      response(source, result => {
        save_download(
          ui_text(result, "content", ""),
          ui_text(result, "filename", "filenest-preview." + format),
        )
      })
    },
  )
}

///|
fn refresh_history() -> Unit {
  if state.root == "" {
    dom_html(
      "history-list", "<p class=\"placeholder\">请先扫描一个文件夹。</p>",
    )
    return
  }
  api_request("/api/history", "{}", source => {
    response(source, result => {
      state.history = ui_array(result, "records")
      render_history(state.history)
    })
  })
}

///|
fn refresh_templates() -> Unit {
  if state.root == "" {
    render_templates()
    return
  }
  api_request("/api/templates", "{}", source => {
    response(source, result => {
      state.built_in_templates = ui_array(result, "builtIn")
      state.custom_templates = ui_array(result, "custom")
      render_templates()
    })
  })
}

///|
fn apply_template(name : String) -> Unit {
  match find_template(name) {
    Some(template) => {
      apply_options(ui_field(template, "options"))
      show_view("organize")
      show_message("已应用模板：“" + name + "”。", false)
      if state.inventory is Object(_) {
        preview_action()
      }
    }
    None => ()
  }
}

///|
fn save_template_action() -> Unit {
  if state.root == "" {
    show_message("请先扫描一个工作文件夹", true)
    return
  }
  let name = browser_prompt("模板名称（最多 40 个字符）")
    .trim()
    .to_owned()
  if name == "" {
    return
  }
  api_request(
    "/api/template/save",
    (
      {
        "name": name,
        "description": "我的整理规则",
        "options": current_options(),
      } : Json).stringify(),
    source => {
      response(source, result => {
        state.built_in_templates = ui_array(result, "builtIn")
        state.custom_templates = ui_array(result, "custom")
        render_templates()
        show_message("模板已保存。", false)
      })
    },
  )
}

///|
fn delete_template_action(name : String) -> Unit {
  if !browser_confirm("删除模板“" + name + "”？") {
    return
  }
  api_request("/api/template/delete", ({ "name": name } : Json).stringify(), source => {
    response(source, result => {
      state.built_in_templates = ui_array(result, "builtIn")
      state.custom_templates = ui_array(result, "custom")
      render_templates()
    })
  })
}

///|
fn undo_action(id : String) -> Unit {
  if !browser_confirm("确认撤销批次 " + id + "？") {
    return
  }
  api_request("/api/undo", ({ "id": id } : Json).stringify(), source => {
    response(source, _ => {
      show_message("撤销完成。", false)
      refresh_history()
    })
  })
}

///|
fn update_rule(action : String, raw_index : String, value : String) -> Unit {
  let index = @string.parse_int(raw_index) catch { _ => return }
  guard index >= 0 && index < state.rules.length() else { return }
  let rule = state.rules[index]
  match action {
    "rule-kind" => {
      rule.kind = value
      render_rules()
    }
    "rule-value" => rule.value = value
    "rule-replacement" => rule.replacement = value
    "rule-remove" => {
      ignore(state.rules.remove(index))
      render_rules()
    }
    "rule-up" =>
      if index > 0 {
        let prior = state.rules[index - 1]
        state.rules[index - 1] = rule
        state.rules[index] = prior
        render_rules()
      }
    "rule-down" =>
      if index + 1 < state.rules.length() {
        let following = state.rules[index + 1]
        state.rules[index + 1] = rule
        state.rules[index] = following
        render_rules()
      }
    _ => ()
  }
}

///|
fn update_category(action : String, raw_index : String, value : String) -> Unit {
  let index = @string.parse_int(raw_index) catch { _ => return }
  guard index >= 0 && index < state.categories.length() else { return }
  let category = state.categories[index]
  match action {
    "category-kind" => category.kind = value
    "category-value" => category.value = value
    "category-folder" => category.folder = value
    "category-remove" => {
      ignore(state.categories.remove(index))
      render_categories()
    }
    _ => ()
  }
}

///|
fn toggle_path(list : Array[String], path : String, selected : Bool) -> Unit {
  let mut index : Int? = None
  for position, item in list {
    if index is None && item == path {
      index = Some(position)
    }
  }
  match (selected, index) {
    (true, None) => list.push(path)
    (false, Some(position)) => ignore(list.remove(position))
    _ => ()
  }
}

///|
fn initialize_events() -> Unit {
  bind_click("scan", scan_action)
  bind_click("preview", preview_action)
  bind_click("duplicate-preview", () => {
    show_view("organize")
    preview_action()
  })
  bind_click("execute", execute_action)
  bind_click("refresh-history", refresh_history)
  bind_click("save-template", save_template_action)
  bind_click("add-rule", () => {
    state.rules.push({ kind: "prefix", value: "", replacement: "", })
    render_rules()
  })
  bind_click("add-category", () => {
    state.categories.push({ kind: "extension", value: "", folder: "", })
    render_categories()
  })
  bind_click("reset", () => {
    state.rules = []
    state.categories = []
    state.excluded = []
    state.quarantine = []
    dom_set_value("classify", "type")
    dom_set_value("conflict", "skip")
    dom_set_value("sort", "name")
    dom_set_value("sequence-start", "1")
    dom_set_value("sequence-width", "3")
    render_rules()
    render_categories()
  })
  bind_change("classify", render_categories)
  bind_change("template-select", () => {
    apply_template(dom_value("template-select"))
  })
  bind_click("export-csv", () => export_action("csv"))
  bind_click("export-json", () => export_action("json"))
  bind_click("export-md", () => export_action("md"))
  bind_delegate("rule-list", update_rule)
  bind_delegate("category-list", update_category)
  bind_delegate("duplicate-list", (action, path, _) => {
    if action == "quarantine" {
      toggle_path(state.quarantine, path, !state.quarantine.contains(path))
    }
  })
  bind_delegate("file-rows", (action, path, _) => {
    if action == "exclude" {
      toggle_path(state.excluded, path, !state.excluded.contains(path))
      preview_action()
    }
  })
  bind_delegate("history-list", (action, id, _) => {
    if action == "undo" {
      undo_action(id)
    }
  })
  bind_delegate("template-cards", (action, name, _) => {
    match action {
      "template-apply" => apply_template(name)
      "template-delete" => delete_template_action(name)
      _ => ()
    }
  })
  bind_delegate("sidebar-nav", (action, view, _) => {
    if action == "view" {
      show_view(view)
    }
  })
}
