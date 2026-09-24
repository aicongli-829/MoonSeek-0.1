///|
/// Small JSON accessors used at the untrusted HTTP and CLI boundaries.
fn json_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn json_text(value : Json, key : String, fallback : String) -> String {
  match json_field(value, key) {
    String(text) => text
    _ => fallback
  }
}

///|
fn json_bool(value : Json, key : String, fallback : Bool) -> Bool {
  match json_field(value, key) {
    true => true
    false => false
    _ => fallback
  }
}

///|
fn json_int64_or(value : Json, key : String, fallback : Int64) -> Int64 {
  match json_field(value, key) {
    Number(number, ..) => number.to_int64()
    String(text) => @string.parse_int64(text) catch { _ => fallback }
    _ => fallback
  }
}

///|
fn json_array(value : Json, key : String) -> Array[Json] {
  match json_field(value, key) {
    Array(values) => values
    _ => []
  }
}

///|
fn json_error(message : String) -> String {
  ({ "error": message } : Json).stringify()
}

///|
fn parse_document(source : String, label : String) -> Json raise {
  @json.parse(source) catch {
    _ => fail(label + " is not valid JSON")
  }
}

///|
/// Generate a collision-resistant identifier without delegating to Node.js.
pub fn operation_id() -> String {
  let bytes = @env.rand(16).unwrap_or_else(() => @env.now().to_be_bytes())
  let out = StringBuilder()
  for i = 0; i < bytes.length(); i = i + 1 {
    let piece = bytes[i].to_uint().to_string(radix=16)
    if piece.length() == 1 {
      out.write_char('0')
    }
    out.write_string(piece)
    if [3, 5, 7, 9].contains(i) {
      out.write_char('-')
    }
  }
  out.to_string()
}
