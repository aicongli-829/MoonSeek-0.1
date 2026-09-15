///|
/// A file inventory item supplied by the operating-system adapter.
pub(all) struct FileEntry {
  path : String
  name : String
  month : String
  size : String
  hash : String
} derive(Eq, Debug, ToJson)

///|
/// Ordered, portable naming operation. Values are validated before execution.
pub(all) struct RenameRule {
  kind : String
  value : String
  replacement : String
} derive(Eq, Debug, ToJson)

///|
/// First matching custom category wins.
pub(all) struct CategoryRule {
  kind : String
  value : String
  folder : String
} derive(Eq, Debug, ToJson)

///|
/// All paths in a plan are relative to one selected root.
pub(all) struct PlanRow {
  source : String
  target : String
  status : String
  reason : String
  category : String
} derive(Eq, Debug, ToJson)

///|
/// Planning options are independent of the clock and filesystem.
pub(all) struct Options {
  classify : String
  conflict : String
  sequence_start : Int
  sequence_width : Int
  sort : String
  rules : Array[RenameRule]
  categories : Array[CategoryRule]
  excluded : Array[String]
  quarantine : Array[String]
} derive(Debug)

///|
pub fn default_options() -> Options {
  {
    classify: "type",
    conflict: "skip",
    sequence_start: 1,
    sequence_width: 3,
    sort: "name",
    rules: [],
    categories: [],
    excluded: [],
    quarantine: [],
  }
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn text_field(value : Json, key : String, fallback : String) -> String {
  match field(value, key) {
    String(text) => text
    _ => fallback
  }
}

///|
fn array_field(value : Json, key : String) -> Array[Json] {
  match field(value, key) {
    Array(items) => items
    _ => []
  }
}

///|
fn strings_field(value : Json, key : String) -> Array[String] {
  array_field(value, key).map(x => {
    match x {
      String(text) => text
      _ => ""
    }
  })
}

///|
fn integer_field(value : Json, key : String, fallback : Int) -> Int {
  match field(value, key) {
    Number(number, ..) => number.to_int()
    String(text) => @string.parse_int(text) catch { _ => fallback }
    _ => fallback
  }
}

///|
fn decode_options(value : Json) -> Options {
  {
    classify: text_field(value, "classify", "type"),
    conflict: text_field(value, "conflict", "skip"),
    sequence_start: integer_field(value, "sequenceStart", 1),
    sequence_width: integer_field(value, "sequenceWidth", 3),
    sort: text_field(value, "sort", "name"),
    rules: array_field(value, "rules").map(rule => {
      kind: text_field(rule, "kind", ""),
      value: text_field(rule, "value", ""),
      replacement: text_field(rule, "replacement", ""),
    }),
    categories: array_field(value, "categories").map(rule => {
      kind: text_field(rule, "kind", ""),
      value: text_field(rule, "value", ""),
      folder: text_field(rule, "folder", ""),
    }),
    excluded: strings_field(value, "excluded"),
    quarantine: strings_field(value, "quarantine"),
  }
}

///|
/// JSON boundary used by both CLI and local HTTP adapter.
/// Never performs filesystem operations and never returns an executable plan
/// when the incoming JSON cannot be decoded.
pub fn plan_json(input : String) -> String {
  let document = @json.parse(input) catch {
    _ => return ({ "error": "输入不是合法 JSON" } : Json).stringify()
  }
  let files : Array[FileEntry] = array_field(document, "files").map(file => {
    path: text_field(file, "path", ""),
    name: text_field(file, "name", ""),
    month: text_field(file, "month", ""),
    size: text_field(file, "size", "0"),
    hash: text_field(file, "hash", ""),
  })
  let options = decode_options(field(document, "options"))
  let errors = validate_options(options)
  if errors.length() > 0 {
    return ({ "error": errors.join("；") } : Json).stringify()
  }
  let rows = plan(files, strings_field(document, "occupied"), options)
  ({ "rows": rows.to_json() } : Json).stringify()
}
