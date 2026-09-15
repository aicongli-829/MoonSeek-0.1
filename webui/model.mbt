///|
priv struct UiRule {
  mut kind : String
  mut value : String
  mut replacement : String
}

///|
priv struct UiCategory {
  mut kind : String
  mut value : String
  mut folder : String
}

///|
priv struct UiState {
  mut root : String
  mut inventory : Json
  mut preview : Json
  mut rules : Array[UiRule]
  mut categories : Array[UiCategory]
  mut excluded : Array[String]
  mut quarantine : Array[String]
  mut history : Array[Json]
  mut built_in_templates : Array[Json]
  mut custom_templates : Array[Json]
}

///|
let state : UiState = {
  root: "",
  inventory: Json::null(),
  preview: Json::null(),
  rules: [],
  categories: [],
  excluded: [],
  quarantine: [],
  history: [],
  built_in_templates: [],
  custom_templates: [],
}

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
    _ => fallback
  }
}

///|
fn ui_scalar(value : Json, key : String, fallback : String) -> String {
  match ui_field(value, key) {
    String(text) => text
    Number(number, ..) => number.to_int().to_string()
    true => "true"
    false => "false"
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
fn comma_values(text : String) -> Array[String] {
  let result : Array[String] = []
  for item in text.split(",") {
    let clean = item.trim().to_owned()
    if clean != "" {
      result.push(clean)
    }
  }
  result
}

///|
fn UiRule::to_json(self : UiRule) -> Json {
  { "kind": self.kind, "value": self.value, "replacement": self.replacement }
}

///|
fn UiCategory::to_json(self : UiCategory) -> Json {
  { "kind": self.kind, "value": self.value, "folder": self.folder }
}

///|
fn current_options() -> Json {
  {
    "classify": dom_value("classify"),
    "conflict": dom_value("conflict"),
    "sort": dom_value("sort"),
    "sequenceStart": dom_value("sequence-start"),
    "sequenceWidth": dom_value("sequence-width"),
    "recursive": dom_checked("recursive"),
    "hidden": dom_checked("hidden-files"),
    "extensions": comma_values(dom_value("extensions")).to_json(),
    "exclude": comma_values(dom_value("exclude")).to_json(),
    "excluded": state.excluded.to_json(),
    "quarantine": state.quarantine.to_json(),
    "rules": state.rules.map(UiRule::to_json).to_json(),
    "categories": state.categories.map(UiCategory::to_json).to_json(),
  }
}

///|
fn json_string_list(value : Json) -> Array[String] {
  match value {
    Array(items) =>
      items.filter_map(item => {
        match item {
          String(text) => Some(text)
          _ => None
        }
      })
    _ => []
  }
}

///|
fn apply_options(options : Json) -> Unit {
  dom_set_value("classify", ui_text(options, "classify", "type"))
  dom_set_value("conflict", ui_text(options, "conflict", "skip"))
  dom_set_value("sort", ui_text(options, "sort", "name"))
  dom_set_value("sequence-start", ui_text(options, "sequenceStart", "1"))
  dom_set_value("sequence-width", ui_text(options, "sequenceWidth", "3"))
  dom_set_checked_value(
    "recursive",
    match ui_field(options, "recursive") {
      true => true
      false => false
      _ => true
    },
  )
  dom_set_checked_value("hidden-files", ui_field(options, "hidden") == true)
  dom_set_value(
    "extensions",
    json_string_list(ui_field(options, "extensions")).join(", "),
  )
  dom_set_value(
    "exclude",
    json_string_list(ui_field(options, "exclude")).join(", "),
  )
  state.excluded = json_string_list(ui_field(options, "excluded"))
  state.quarantine = json_string_list(ui_field(options, "quarantine"))
  state.rules = ui_array(options, "rules").map(raw => {
    kind: ui_text(raw, "kind", "prefix"),
    value: ui_text(raw, "value", ""),
    replacement: ui_text(raw, "replacement", ""),
  })
  state.categories = ui_array(options, "categories").map(raw => {
    kind: ui_text(raw, "kind", "extension"),
    value: ui_text(raw, "value", ""),
    folder: ui_text(raw, "folder", ""),
  })
  render_rules()
  render_categories()
}

///|
fn all_templates() -> Array[Json] {
  let result = state.built_in_templates.copy()
  result.push_iter(state.custom_templates.iter())
  result
}

///|
fn find_template(name : String) -> Json? {
  all_templates().iter().find_first(item => ui_text(item, "name", "") == name)
}

///|
fn response(source : String, callback : (Json) -> Unit) -> Unit {
  let document = @json.parse(source) catch {
    _ => {
      show_message("服务器返回了无法读取的内容", true)
      return
    }
  }
  match ui_field(document, "error") {
    String(message) => show_message(message, true)
    _ => callback(document)
  }
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
