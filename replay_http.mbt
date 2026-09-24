///|
let supported_methods : Array[String] = [
  "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE",
]

///|
fn normalize_method(value : String) -> String {
  let verb = uppercase(value)
  if supported_methods.contains(verb) {
    verb
  } else {
    verb
  }
}

///|
fn hex_value(character : UInt16) -> Int? {
  let code = character.to_int()
  if code >= 48 && code <= 57 {
    Some(code - 48)
  } else if code >= 97 && code <= 102 {
    Some(code - 97 + 10)
  } else if code >= 65 && code <= 70 {
    Some(code - 65 + 10)
  } else {
    None
  }
}

///|
fn percent_decode(source : String, plus_as_space? : Bool = false) -> String {
  let output = StringBuilder()
  let mut index = 0
  while index < source.length() {
    if source[index] == '%' && index + 2 < source.length() {
      let high = hex_value(source[index + 1])
      let low = hex_value(source[index + 2])
      match (high, low) {
        (Some(a), Some(b)) => {
          output.write_char((a * 16 + b).to_byte().to_char())
          index = index + 3
        }
        _ => {
          output.write_char('%')
          index = index + 1
        }
      }
    } else if plus_as_space && source[index] == '+' {
      output.write_char(' ')
      index = index + 1
    } else {
      output.write_char(source[index].to_char().unwrap_or('\u{fffd}'))
      index = index + 1
    }
  }
  output.to_string()
}

///|
fn split_target(target : String) -> (String, String) {
  match target.find("?") {
    Some(index) => (target[:index].to_owned(), target[index + 1:].to_owned())
    None => (target, "")
  }
}

///|
fn normalize_path(source : String) -> String {
  let (path, _) = split_target(source.trim().to_owned())
  let clean = if path == "" { "/" } else { path }
  let output : Array[String] = []
  for segment in clean.split("/") {
    let decoded = percent_decode(segment.to_owned())
    if decoded == "" || decoded == "." {
      continue
    }
    if decoded == ".." {
      if output.length() > 0 {
        ignore(output.pop())
      }
    } else {
      output.push(decoded)
    }
  }
  "/" + output.join("/")
}

///|
fn parse_query(source : String) -> Array[Json] {
  let query = match source.find("?") {
    Some(index) => source[index + 1:].to_owned()
    None => source
  }
  let rows : Array[Json] = []
  if query == "" {
    return rows
  }
  for piece in query.split("&") {
    let item = piece.to_owned()
    let (name, value) = match item.find("=") {
      Some(index) => (item[:index].to_owned(), item[index + 1:].to_owned())
      None => (item, "")
    }
    rows.push({
      "name": percent_decode(name, plus_as_space=true),
      "value": percent_decode(value, plus_as_space=true),
    })
  }
  rows
}

///|
fn canonical_headers(rows : Array[Json]) -> Array[Json] {
  let merged : Map[String, Array[String]] = Map([])
  for row in rows {
    let name = lowercase(replay_text(row, "name", ""))
    if name == "" {
      continue
    }
    let values = merged.get(name).unwrap_or([])
    values.push(replay_text(row, "value", "").trim().to_owned())
    merged[name] = values
  }
  let names = merged.keys().collect()
  names.sort()
  names.map(name => ({ "name": name, "value": merged[name].join(", ") } : Json))
}

///|
fn header_value(request : Json, name : String) -> String? {
  let wanted = lowercase(name)
  for row in replay_array(request, "headers") {
    if lowercase(replay_text(row, "name", "")) == wanted {
      return Some(replay_text(row, "value", ""))
    }
  }
  None
}

///|
fn query_values(request : Json, name : String) -> Array[String] {
  replay_array(request, "query").filter_map(row => {
    if replay_text(row, "name", "") == name {
      Some(replay_text(row, "value", ""))
    } else {
      None
    }
  })
}

///|
fn normalize_request(input : Json) -> Json {
  let raw_target = replay_text(input, "target", replay_text(input, "path", "/"))
  let supplied_query = replay_array(input, "query")
  {
    "id": replay_text(input, "id", ""),
    "receivedAt": replay_text(input, "receivedAt", ""),
    "method": normalize_method(replay_text(input, "method", "GET")),
    "target": raw_target,
    "path": normalize_path(raw_target),
    "query": if supplied_query.length() > 0 {
      supplied_query
    } else {
      parse_query(raw_target)
    },
    "headers": canonical_headers(replay_array(input, "headers")),
    "body": replay_text(input, "body", ""),
    "remoteAddress": replay_text(input, "remoteAddress", ""),
  }
}

///|
fn request_summary(request : Json) -> Json {
  let normalized = normalize_request(request)
  let body = replay_text(normalized, "body", "")
  {
    "id": replay_text(normalized, "id", ""),
    "receivedAt": replay_text(normalized, "receivedAt", ""),
    "method": replay_text(normalized, "method", ""),
    "path": replay_text(normalized, "path", ""),
    "queryCount": replay_array(normalized, "query").length(),
    "headerCount": replay_array(normalized, "headers").length(),
    "bodyBytes": body.length(),
  }
}

///|
fn shell_quote(value : String) -> String {
  if value != "" &&
    !value.contains(" ") &&
    !value.contains("\"") &&
    !value.contains("'") &&
    !value.contains("$") {
    return value
  }
  "'" + value.replace_all(old="'", new="'\"'\"'") + "'"
}

///|
pub fn export_curl_json(source : String) -> String {
  try {
    let input = replay_parse(source, "curl input")
    let request = normalize_request(replay_field(input, "request"))
    let base_url = replay_text(input, "baseUrl", "http://127.0.0.1:8080")
      .trim_end(chars=['/'])
      .to_owned()
    let parts : Array[String] = [
      "curl",
      "-i",
      "-X",
      replay_text(request, "method", "GET"),
    ]
    for header in replay_array(request, "headers") {
      let name = replay_text(header, "name", "")
      if !["host", "content-length"].contains(name) {
        parts.push("-H")
        parts.push(shell_quote(name + ": " + replay_text(header, "value", "")))
      }
    }
    let body = replay_text(request, "body", "")
    if body != "" {
      parts.push("--data-binary")
      parts.push(shell_quote(body))
    }
    parts.push(shell_quote(base_url + replay_text(request, "target", "/")))
    replay_result({ "command": parts.join(" ") })
  } catch {
    error => replay_error(error.to_string())
  }
}
