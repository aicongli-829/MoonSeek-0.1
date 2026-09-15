///|
priv struct ApplicationState {
  initial_root : String
  token : String
  origin : String
  mut root : String
  mut inventory : Json
  mut preview : Json
}

///|
fn ApplicationState::new(initial_root : String, port : Int) -> ApplicationState {
  {
    initial_root,
    token: operation_id() + operation_id(),
    origin: "http://127.0.0.1:" + port.to_string(),
    root: "",
    inventory: Json::null(),
    preview: Json::null(),
  }
}

///|
fn ApplicationState::has_inventory(self : ApplicationState) -> Bool {
  self.inventory is Object(_)
}

///|
fn ApplicationState::has_preview(self : ApplicationState) -> Bool {
  self.preview is Object(_)
}

///|
async fn ApplicationState::scan(self : ApplicationState, input : Json) -> Json {
  let root_input = json_text(input, "root", "")
  guard root_input.trim() != "" else { fail("请输入文件夹路径") }
  let options = json_field(input, "options")
  let response = parse_document(
    scan_json(root_input, options.stringify()),
    "扫描结果",
  )
  match json_field(response, "error") {
    String(message) => fail(message)
    _ => ()
  }
  self.root = json_text(response, "root", "")
  self.inventory = json_field(response, "inventory")
  self.preview = Json::null()
  { "root": self.root, "inventory": self.inventory }
}

///|
fn ApplicationState::preview_plan(
  self : ApplicationState,
  input : Json,
) -> Json raise {
  guard self.has_inventory() else { fail("请先扫描文件夹") }
  let options_source = json_field(input, "options").stringify()
  let checked = parse_document(
    @core.validate_options_json(options_source),
    "设置结果",
  )
  match json_field(checked, "error") {
    String(message) => fail(message)
    _ => ()
  }
  let options = json_field(checked, "options")
  let request : Json = {
    "files": json_field(self.inventory, "files"),
    "occupied": json_field(self.inventory, "occupied"),
    "directories": json_field(self.inventory, "directories"),
    "duplicates": json_field(self.inventory, "duplicates"),
    "options": options,
  }
  let planned = parse_document(
    @core.plan_bundle_json(request.stringify()),
    "预览结果",
  )
  match json_field(planned, "error") {
    String(message) => fail(message)
    _ => ()
  }
  self.preview = {
    "id": operation_id(),
    "created": @env.now().to_string(),
    "rows": json_field(planned, "rows"),
    "options": options,
    "summary": json_field(planned, "summary"),
  }
  self.preview
}

///|
async fn ApplicationState::execute(
  self : ApplicationState,
  input : Json,
) -> Json {
  guard self.has_preview() else { fail("请先生成最新预览") }
  guard json_text(input, "planId", "") == json_text(self.preview, "id", "") else {
    fail("预览已失效，请重新生成")
  }
  guard json_field(input, "confirm") == true else {
    fail("执行前需要确认")
  }
  let result = parse_document(
    execute_json(
      self.root,
      self.preview.stringify(),
      self.inventory.stringify(),
    ),
    "执行结果",
  )
  self.preview = Json::null()
  self.inventory = Json::null()
  result
}

///|
fn ApplicationState::export_report(
  self : ApplicationState,
  input : Json,
) -> Json raise {
  guard self.has_preview() else { fail("请先生成最新预览") }
  let format = json_text(input, "format", "json")
  guard ["json", "csv", "md"].contains(format) else {
    fail("不支持的报告格式")
  }
  let result = parse_document(
    @core.report_json(
      ({ "format": format, "plan": self.preview } : Json).stringify(),
    ),
    "导出结果",
  )
  match json_field(result, "error") {
    String(message) => fail(message)
    _ =>
      {
        "content": json_field(result, "content"),
        "filename": "filenest-preview." + format,
      }
  }
}

///|
async fn ApplicationState::dispatch(
  self : ApplicationState,
  path : String,
  input : Json,
) -> Json {
  match path {
    "/api/scan" => self.scan(input)
    "/api/preview" => self.preview_plan(input)
    "/api/execute" => self.execute(input)
    "/api/history" => {
      guard self.root != "" else { fail("请先扫描文件夹") }
      parse_document(history_json(self.root), "历史记录")
    }
    "/api/undo" => {
      guard self.root != "" else { fail("请先扫描文件夹") }
      parse_document(
        undo_json(self.root, json_text(input, "id", "")),
        "撤销结果",
      )
    }
    "/api/export" => self.export_report(input)
    "/api/templates" => {
      guard self.root != "" else { fail("请先扫描文件夹") }
      all_templates_json(self.root)
    }
    "/api/template/save" => {
      guard self.root != "" else { fail("请先扫描文件夹") }
      save_template(self.root, input)
    }
    "/api/template/delete" => {
      guard self.root != "" else { fail("请先扫描文件夹") }
      delete_template(self.root, json_text(input, "name", ""))
    }
    "/api/analyze" => {
      guard self.has_inventory() else { fail("请先扫描文件夹") }
      parse_document(
        @core.analyze_inventory_json(
          (
            {
              "files": json_field(self.inventory, "files"),
              "duplicates": json_field(self.inventory, "duplicates"),
            } : Json).stringify(),
        ),
        "分析结果",
      )
    }
    "/api/snapshot" => {
      guard self.has_inventory() else { fail("请先扫描文件夹") }
      parse_document(
        @core.create_snapshot_json(
          (
            {
              "created": @env.now().to_string(),
              "files": json_field(self.inventory, "files"),
            } : Json).stringify(),
        ),
        "快照结果",
      )
    }
    _ => fail("接口不存在")
  }
}
