///|
/// JSON boundary helpers shared by the portable MoonReplay core.
fn replay_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn replay_text(value : Json, key : String, fallback : String) -> String {
  match replay_field(value, key) {
    String(text) => text
    _ => fallback
  }
}

///|
fn replay_bool(value : Json, key : String, fallback : Bool) -> Bool {
  match replay_field(value, key) {
    true => true
    false => false
    _ => fallback
  }
}

///|
fn replay_int(value : Json, key : String, fallback : Int) -> Int {
  match replay_field(value, key) {
    Number(number, ..) => number.to_int()
    String(text) => @string.parse_int(text) catch { _ => fallback }
    _ => fallback
  }
}

///|
fn replay_int64(value : Json, key : String, fallback : Int64) -> Int64 {
  match replay_field(value, key) {
    Number(number, ..) => number.to_int64()
    String(text) => @string.parse_int64(text) catch { _ => fallback }
    _ => fallback
  }
}

///|
fn replay_array(value : Json, key : String) -> Array[Json] {
  match replay_field(value, key) {
    Array(items) => items
    _ => []
  }
}

///|
fn replay_strings(value : Json, key : String) -> Array[String] {
  replay_array(value, key).filter_map(item => {
    match item {
      String(text) => Some(text)
      _ => None
    }
  })
}

///|
fn replay_parse(source : String, label : String) -> Json raise {
  @json.parse(source) catch {
    _ => fail(label + " is not valid JSON")
  }
}

///|
fn try_parse_json(source : String) -> Json? {
  Some(@json.parse(source)) catch {
    _ => None
  }
}

///|
fn replay_error(message : String) -> String {
  ({ "error": message } : Json).stringify()
}

///|
fn replay_result(body : Json) -> String {
  body.stringify()
}

///|
fn lowercase(value : String) -> String {
  value.trim().to_owned().to_lower()
}

///|
fn uppercase(value : String) -> String {
  value.trim().to_owned().to_upper()
}

///|
fn json_type_name(value : Json) -> String {
  match value {
    Null => "null"
    true | false => "boolean"
    Number(_) => "number"
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
fn string_map_to_rows(values : Map[String, String]) -> Array[Json] {
  let keys = values.keys().collect()
  keys.sort()
  keys.map(key => ({ "name": key, "value": values[key] } : Json))
}

///|
fn rows_to_string_map(
  rows : Array[Json],
  normalize_names? : Bool = false,
) -> Map[String, String] {
  let values : Map[String, String] = Map([])
  for row in rows {
    let raw_name = replay_text(row, "name", "").trim().to_owned()
    if raw_name != "" {
      let name = if normalize_names { raw_name.to_lower() } else { raw_name }
      values[name] = replay_text(row, "value", "")
    }
  }
  values
}

///|
fn json_scalar_text(value : Json) -> String {
  match value {
    Null => "null"
    true => "true"
    false => "false"
    Number(number, ..) => number.to_string()
    String(text) => text
    Array(_) | Object(_) => value.stringify()
  }
}

///|
fn clamp_int(value : Int, minimum : Int, maximum : Int) -> Int {
  value.max(minimum).min(maximum)
}

///|
fn stable_json(value : Json) -> String {
  match value {
    Object(fields) => {
      let keys = fields.keys().collect()
      keys.sort()
      let pieces : Array[String] = []
      for key in keys {
        pieces.push(
          Json::string(key).stringify() + ":" + stable_json(fields[key]),
        )
      }
      "{" + pieces.join(",") + "}"
    }
    Array(items) => "[" + items.map(stable_json).join(",") + "]"
    _ => value.stringify()
  }
}
