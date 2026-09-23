///|
fn search_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn search_text(value : Json, key : String, fallback : String) -> String {
  match search_field(value, key) {
    String(text) => text
    _ => fallback
  }
}

///|
fn search_int(value : Json, key : String, fallback : Int) -> Int {
  match search_field(value, key) {
    Number(number, ..) => number.to_int()
    String(text) => @string.parse_int(text) catch { _ => fallback }
    _ => fallback
  }
}

///|
fn search_int64(value : Json, key : String, fallback : Int64) -> Int64 {
  match search_field(value, key) {
    Number(number, ..) => number.to_int64()
    String(text) => @string.parse_int64(text) catch { _ => fallback }
    _ => fallback
  }
}

///|
fn search_array(value : Json, key : String) -> Array[Json] {
  match search_field(value, key) {
    Array(items) => items
    _ => []
  }
}

///|
fn search_parse(source : String, label : String) -> Json raise {
  @json.parse(source) catch {
    _ => fail(label + " is not valid JSON")
  }
}

///|
fn search_error(message : String) -> String {
  ({ "error": message } : Json).stringify()
}
