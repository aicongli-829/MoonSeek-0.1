///|
priv struct MatchFinding {
  mut matched : Bool
  mut score : Int
  variables : Map[String, String]
  reasons : Array[String]
}

///|
fn MatchFinding::success(score? : Int = 0) -> MatchFinding {
  { matched: true, score, variables: Map([]), reasons: [], }
}

///|
fn MatchFinding::failure(reason : String) -> MatchFinding {
  { matched: false, score: 0, variables: Map([]), reasons: [reason], }
}

///|
fn finding_json(finding : MatchFinding) -> Json {
  {
    "matched": finding.matched,
    "score": finding.score,
    "variables": string_map_to_rows(finding.variables).to_json(),
    "reasons": finding.reasons.to_json(),
  }
}

///|
fn segment_is_parameter(segment : String) -> Bool {
  segment.length() >= 3 && segment.has_prefix("{") && segment.has_suffix("}")
}

///|
fn parameter_name(segment : String) -> String {
  if segment_is_parameter(segment) {
    segment[1:segment.length() - 1].to_owned().trim().to_owned()
  } else {
    ""
  }
}

///|
fn path_segments(path : String) -> Array[String] {
  normalize_path(path)
  .trim(chars=['/'])
  .split("/")
  .filter_map(piece => {
    let text = piece.to_owned()
    if text == "" {
      None
    } else {
      Some(text)
    }
  })
  .collect()
}

///|
fn match_template_path(pattern : String, actual : String) -> MatchFinding {
  let expected = path_segments(pattern)
  let received = path_segments(actual)
  if expected.length() != received.length() {
    return MatchFinding::failure(
      "path has " +
      received.length().to_string() +
      " segments; expected " +
      expected.length().to_string(),
    )
  }
  let finding = MatchFinding::success(score=20)
  for index, segment in expected {
    let candidate = received[index]
    if segment_is_parameter(segment) {
      let name = parameter_name(segment)
      if name == "" {
        return MatchFinding::failure(
          "path template contains an empty parameter",
        )
      }
      finding.variables[name] = candidate
      finding.score = finding.score + 4
    } else if segment != candidate {
      return MatchFinding::failure(
        "path segment " +
        index.to_string() +
        " expected '" +
        segment +
        "' but received '" +
        candidate +
        "'",
      )
    } else {
      finding.score = finding.score + 8
    }
  }
  finding
}

///|
fn wildcard_match(pattern : String, value : String) -> Bool {
  let rows = pattern.length() + 1
  let columns = value.length() + 1
  let table : Array[Array[Bool]] = Array::makei(rows, _ => {
    Array::make(columns, false)
  })
  table[0][0] = true
  for row = 1; row < rows; row = row + 1 {
    if pattern[row - 1] == '*' {
      table[row][0] = table[row - 1][0]
    }
  }
  for row = 1; row < rows; row = row + 1 {
    for column = 1; column < columns; column = column + 1 {
      let token = pattern[row - 1]
      if token == '*' {
        table[row][column] = table[row - 1][column] || table[row][column - 1]
      } else if token == '?' || token == value[column - 1] {
        table[row][column] = table[row - 1][column - 1]
      }
    }
  }
  table[rows - 1][columns - 1]
}

///|
fn match_path_rule(rule : Json, request : Json) -> MatchFinding {
  let pattern = replay_text(rule, "path", "/")
  let actual = replay_text(request, "path", "/")
  match lowercase(replay_text(rule, "pathMode", "exact")) {
    "exact" =>
      if normalize_path(pattern) == actual {
        MatchFinding::success(score=100)
      } else {
        MatchFinding::failure("path does not equal " + normalize_path(pattern))
      }
    "prefix" =>
      if actual.has_prefix(normalize_path(pattern)) {
        MatchFinding::success(score=60 + normalize_path(pattern).length())
      } else {
        MatchFinding::failure(
          "path does not start with " + normalize_path(pattern),
        )
      }
    "template" => match_template_path(pattern, actual)
    "wildcard" =>
      if wildcard_match(pattern, actual) {
        MatchFinding::success(score=40 + pattern.length())
      } else {
        MatchFinding::failure("path does not match wildcard " + pattern)
      }
    unknown => MatchFinding::failure("unknown path mode " + unknown)
  }
}

///|
fn compare_text(actual : String?, operator : String, expected : String) -> Bool {
  let op = lowercase(operator)
  match op {
    "present" => actual is Some(_)
    "absent" => actual is None
    "equals" | "exact" => actual.unwrap_or("") == expected
    "equals-ignore-case" =>
      lowercase(actual.unwrap_or("")) == lowercase(expected)
    "contains" => actual.unwrap_or("").contains(expected)
    "contains-ignore-case" =>
      lowercase(actual.unwrap_or("")).contains(lowercase(expected))
    "prefix" => actual.unwrap_or("").has_prefix(expected)
    "suffix" => actual.unwrap_or("").has_suffix(expected)
    "wildcard" => wildcard_match(expected, actual.unwrap_or(""))
    _ => false
  }
}

///|
fn match_named_conditions(
  conditions : Array[Json],
  values : (String) -> Array[String],
  label : String,
) -> MatchFinding {
  let finding = MatchFinding::success()
  for condition in conditions {
    let name = replay_text(condition, "name", "")
    let operator = replay_text(condition, "operator", "equals")
    let expected = replay_text(condition, "value", "")
    let candidates = values(name)
    let actual = if candidates.length() > 0 {
      Some(candidates.join(", "))
    } else {
      None
    }
    if !compare_text(actual, operator, expected) {
      finding.matched = false
      finding.reasons.push(
        label + " '" + name + "' failed " + operator + " comparison",
      )
    } else {
      finding.score = finding.score + 6
    }
  }
  finding
}

///|
fn json_contains(expected : Json, actual : Json) -> Bool {
  match expected {
    Object(expected_fields) =>
      match actual {
        Object(actual_fields) => {
          for key, expected_value in expected_fields {
            match actual_fields.get(key) {
              Some(actual_value) =>
                if !json_contains(expected_value, actual_value) {
                  return false
                }
              None => return false
            }
          }
          true
        }
        _ => false
      }
    Array(expected_items) =>
      match actual {
        Array(actual_items) => {
          if expected_items.length() > actual_items.length() {
            return false
          }
          for index, expected_value in expected_items {
            if !json_contains(expected_value, actual_items[index]) {
              return false
            }
          }
          true
        }
        _ => false
      }
    _ => stable_json(expected) == stable_json(actual)
  }
}

///|
fn match_body_rule(rule : Json, request : Json) -> MatchFinding {
  let body_rule = replay_field(rule, "body")
  let mode = lowercase(replay_text(body_rule, "mode", "any"))
  let expected = replay_text(body_rule, "value", "")
  let actual = replay_text(request, "body", "")
  match mode {
    "" | "any" => MatchFinding::success()
    "empty" =>
      if actual == "" {
        MatchFinding::success(score=5)
      } else {
        MatchFinding::failure("request body is not empty")
      }
    "exact" =>
      if actual == expected {
        MatchFinding::success(score=30)
      } else {
        MatchFinding::failure("request body differs from the expected text")
      }
    "contains" =>
      if actual.contains(expected) {
        MatchFinding::success(score=15)
      } else {
        MatchFinding::failure("request body does not contain the expected text")
      }
    "json" | "json-exact" => {
      let parsed_expected = replay_parse(expected, "expected request body") catch {
        _ =>
          return MatchFinding::failure("route contains invalid expected JSON")
      }
      let parsed_actual = replay_parse(actual, "actual request body") catch {
        _ => return MatchFinding::failure("request body is not JSON")
      }
      if stable_json(parsed_expected) == stable_json(parsed_actual) {
        MatchFinding::success(score=40)
      } else {
        MatchFinding::failure("request JSON differs from the expected value")
      }
    }
    "json-subset" => {
      let parsed_expected = replay_parse(expected, "expected request body") catch {
        _ =>
          return MatchFinding::failure("route contains invalid expected JSON")
      }
      let parsed_actual = replay_parse(actual, "actual request body") catch {
        _ => return MatchFinding::failure("request body is not JSON")
      }
      if json_contains(parsed_expected, parsed_actual) {
        MatchFinding::success(score=35)
      } else {
        MatchFinding::failure(
          "request JSON does not contain the expected fields",
        )
      }
    }
    unknown => MatchFinding::failure("unknown body match mode " + unknown)
  }
}

///|
fn combine_findings(findings : Array[MatchFinding]) -> MatchFinding {
  let combined = MatchFinding::success()
  for finding in findings {
    combined.matched = combined.matched && finding.matched
    combined.score = combined.score + finding.score
    for key, value in finding.variables {
      combined.variables[key] = value
    }
    for reason in finding.reasons {
      combined.reasons.push(reason)
    }
  }
  combined
}

///|
fn match_request(route : Json, input : Json) -> MatchFinding {
  if !replay_bool(route, "enabled", true) {
    return MatchFinding::failure("route is disabled")
  }
  let request = normalize_request(input)
  let rule = replay_field(route, "match")
  let methods = replay_strings(rule, "methods").map(uppercase)
  let actual_method = replay_text(request, "method", "GET")
  let method_finding = if methods.length() == 0 ||
    methods.contains(actual_method) {
    MatchFinding::success(score=if methods.length() == 0 { 0 } else { 20 })
  } else {
    MatchFinding::failure("method " + actual_method + " is not accepted")
  }
  let headers = match_named_conditions(
    replay_array(rule, "headers"),
    name => {
      match header_value(request, name) {
        Some(value) => [value]
        None => []
      }
    },
    "header",
  )
  let query = match_named_conditions(
    replay_array(rule, "query"),
    name => query_values(request, name),
    "query parameter",
  )
  combine_findings([
    method_finding,
    match_path_rule(rule, request),
    headers,
    query,
    match_body_rule(rule, request),
  ])
}

///|
pub fn match_request_json(source : String) -> String {
  try {
    let input = replay_parse(source, "match input")
    replay_result(
      finding_json(
        match_request(
          replay_field(input, "route"),
          replay_field(input, "request"),
        ),
      ),
    )
  } catch {
    error => replay_error(error.to_string())
  }
}

///|
fn select_route(routes : Array[Json], request : Json) -> Json {
  let evaluations : Array[Json] = []
  let mut selected : Json? = None
  let mut selected_score = -1
  let mut selected_priority = -2147483647
  for route in routes {
    let finding = match_request(route, request)
    let priority = replay_int(route, "priority", 0)
    evaluations.push({
      "id": replay_text(route, "id", ""),
      "name": replay_text(route, "name", ""),
      "priority": priority,
      "result": finding_json(finding),
    })
    if finding.matched &&
      (
        priority > selected_priority ||
        (priority == selected_priority && finding.score > selected_score)
      ) {
      selected = Some(route)
      selected_priority = priority
      selected_score = finding.score
    }
  }
  {
    "matched": selected is Some(_),
    "route": selected.unwrap_or(Json::null()),
    "score": selected_score.max(0),
    "evaluations": evaluations.to_json(),
  }
}

///|
pub fn select_route_json(source : String) -> String {
  try {
    let input = replay_parse(source, "route selection input")
    replay_result(
      select_route(
        replay_array(input, "routes"),
        replay_field(input, "request"),
      ),
    )
  } catch {
    error => replay_error(error.to_string())
  }
}
