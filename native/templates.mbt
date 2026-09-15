///|
async fn custom_templates(root : String) -> Array[Json] {
  let state = ensure_state(root)
  let path = native_path(state, "templates.json")
  if !@fs.exists(path) {
    return []
  }
  let document = parse_document(read_text(path), "模板文件")
  guard document is Array(items) else { fail("模板文件格式错误") }
  items
}

///|
async fn all_templates_json(root : String) -> Json {
  let defaults = parse_document(
    @core.configuration_defaults_json("{}"),
    "默认模板",
  )
  {
    "builtIn": json_field(defaults, "builtInTemplates"),
    "custom": custom_templates(root).to_json(),
  }
}

///|
async fn save_template(root : String, input : Json) -> Json {
  let validated = parse_document(
    @core.validate_template_json(input.stringify()),
    "模板校验",
  )
  match json_field(validated, "error") {
    String(message) => fail(message)
    _ => ()
  }
  let template = json_field(validated, "template")
  let name = json_text(template, "name", "")
  let items = custom_templates(root).filter(item => {
    json_text(item, "name", "") != name
  })
  guard items.length() < 30 else { fail("最多保存 30 个自定义模板") }
  items.push(template)
  let state = ensure_state(root)
  atomic_text(
    native_path(state, "templates.json"),
    items.to_json().stringify(indent=2),
  )
  all_templates_json(root)
}

///|
async fn delete_template(root : String, name : String) -> Json {
  let items = custom_templates(root).filter(item => {
    json_text(item, "name", "") != name
  })
  let state = ensure_state(root)
  atomic_text(
    native_path(state, "templates.json"),
    items.to_json().stringify(indent=2),
  )
  all_templates_json(root)
}
