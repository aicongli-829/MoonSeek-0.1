///|
fn lookup_json_path(value : Json, path : Array[String]) -> Json? {
  let mut current = value
  for segment in path {
    match current {
      Object(fields) =>
        match fields.get(segment) {
          Some(next) => current = next
          None => return None
        }
      Array(items) => {
        let index = @string.parse_int(segment) catch { _ => return None }
        if index < 0 || index >= items.length() {
          return None
        }
        current = items[index]
      }
      _ => return None
    }
  }
  Some(current)
}

///|
fn template_variable(
  expression : String,
  request : Json,
  variables : Map[String, String],
) -> String? {
  let clean = expression.trim().to_owned()
  if clean.has_prefix("path.") {
    return variables.get(clean[5:].to_owned())
  }
  if clean.has_prefix("query.") {
    let values = query_values(request, clean[6:].to_owned())
    return if values.length() > 0 { Some(values[0]) } else { None }
  }
  if clean.has_prefix("header.") {
    return header_value(request, clean[7:].to_owned())
  }
  if clean.has_prefix("body.") {
    let body = replay_parse(replay_text(request, "body", ""), "request body") catch {
      _ => return None
    }
    return lookup_json_path(
      body,
      clean[5:].to_owned().split(".").map(x => x.to_owned()).collect(),
    ).map(json_scalar_text)
  }
  match clean {
    "request.method" => Some(replay_text(request, "method", ""))
    "request.path" => Some(replay_text(request, "path", ""))
    "request.target" => Some(replay_text(request, "target", ""))
    "request.body" => Some(replay_text(request, "body", ""))
    _ => variables.get(clean)
  }
}

///|
fn render_template(
  source : String,
  request : Json,
  variables : Map[String, String],
) -> String {
  let output = StringBuilder()
  let mut cursor = 0
  while cursor < source.length() {
    let tail = source[cursor:].to_owned()
    match tail.find("{{") {
      None => {
        output.write_string(tail)
        cursor = source.length()
      }
      Some(relative_start) => {
        let start = cursor + relative_start
        output.write_string(source[cursor:start].to_owned())
        let after_start = start + 2
        let remaining = source[after_start:].to_owned()
        match remaining.find("}}") {
          None => {
            output.write_string(source[start:].to_owned())
            cursor = source.length()
          }
          Some(relative_end) => {
            let end = after_start + relative_end
            let expression = source[after_start:end].to_owned()
            output.write_string(
              template_variable(expression, request, variables).unwrap_or(""),
            )
            cursor = end + 2
          }
        }
      }
    }
  }
  output.to_string()
}

///|
fn render_response(route : Json, input : Json) -> Json {
  let request = normalize_request(input)
  let finding = match_request(route, request)
  let response = replay_field(route, "response")
  let rendered_headers = replay_array(response, "headers").map(row => {
    (
      {
        "name": replay_text(row, "name", ""),
        "value": render_template(
          replay_text(row, "value", ""),
          request,
          finding.variables,
        ),
      } : Json)
  })
  {
    "status": clamp_int(replay_int(response, "status", 200), 100, 599),
    "headers": rendered_headers.to_json(),
    "body": render_template(
      replay_text(response, "body", ""),
      request,
      finding.variables,
    ),
    "delayMs": clamp_int(replay_int(response, "delayMs", 0), 0, 30000),
    "matched": finding.matched,
    "variables": string_map_to_rows(finding.variables).to_json(),
  }
}

///|
pub fn render_response_json(source : String) -> String {
  try {
    let input = replay_parse(source, "render input")
    replay_result(
      render_response(
        replay_field(input, "route"),
        replay_field(input, "request"),
      ),
    )
  } catch {
    error => replay_error(error.to_string())
  }
}
