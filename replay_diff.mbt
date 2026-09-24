///|
priv struct Difference {
  path : String
  kind : String
  expected : Json
  actual : Json
  message : String
}

///|
fn difference_json(item : Difference) -> Json {
  {
    "path": item.path,
    "kind": item.kind,
    "expected": item.expected,
    "actual": item.actual,
    "message": item.message,
  }
}

///|
fn add_difference(
  differences : Array[Difference],
  path : String,
  kind : String,
  expected : Json,
  actual : Json,
  message : String,
) -> Unit {
  differences.push({ path, kind, expected, actual, message, })
}

///|
fn child_path(parent : String, name : String) -> String {
  if parent == "$" {
    "$." + name
  } else {
    parent + "." + name
  }
}

///|
fn compare_json_values(
  expected : Json,
  actual : Json,
  path : String,
  differences : Array[Difference],
  max_differences : Int,
) -> Unit {
  if differences.length() >= max_differences {
    return
  }
  if json_type_name(expected) != json_type_name(actual) {
    add_difference(
      differences,
      path,
      "type",
      expected,
      actual,
      "expected " +
      json_type_name(expected) +
      " but received " +
      json_type_name(actual),
    )
    return
  }
  match (expected, actual) {
    (Object(expected_fields), Object(actual_fields)) => {
      let expected_keys = expected_fields.keys().collect()
      expected_keys.sort()
      for key in expected_keys {
        if differences.length() >= max_differences {
          return
        }
        match actual_fields.get(key) {
          Some(actual_value) =>
            compare_json_values(
              expected_fields[key],
              actual_value,
              child_path(path, key),
              differences,
              max_differences,
            )
          None =>
            add_difference(
              differences,
              child_path(path, key),
              "missing",
              expected_fields[key],
              Json::null(),
              "property is missing",
            )
        }
      }
      let actual_keys = actual_fields.keys().collect()
      actual_keys.sort()
      for key in actual_keys {
        if differences.length() >= max_differences {
          return
        }
        if !expected_fields.contains(key) {
          add_difference(
            differences,
            child_path(path, key),
            "unexpected",
            Json::null(),
            actual_fields[key],
            "property was not expected",
          )
        }
      }
    }
    (Array(expected_items), Array(actual_items)) => {
      let shared = expected_items.length().min(actual_items.length())
      for index = 0; index < shared; index = index + 1 {
        compare_json_values(
          expected_items[index],
          actual_items[index],
          path + "[" + index.to_string() + "]",
          differences,
          max_differences,
        )
      }
      if expected_items.length() != actual_items.length() &&
        differences.length() < max_differences {
        add_difference(
          differences,
          path,
          "length",
          expected_items.length().to_json(),
          actual_items.length().to_json(),
          "array length changed",
        )
      }
    }
    _ =>
      if stable_json(expected) != stable_json(actual) {
        add_difference(
          differences, path, "value", expected, actual, "value changed",
        )
      }
  }
}

///|
fn header_map(response : Json, ignored : Array[String]) -> Map[String, String] {
  let output : Map[String, String] = Map([])
  for row in replay_array(response, "headers") {
    let name = lowercase(replay_text(row, "name", ""))
    if name != "" && !ignored.contains(name) {
      output[name] = replay_text(row, "value", "").trim().to_owned()
    }
  }
  output
}

///|
fn compare_headers(
  expected : Json,
  actual : Json,
  ignored : Array[String],
  differences : Array[Difference],
  max_differences : Int,
) -> Unit {
  let left = header_map(expected, ignored)
  let right = header_map(actual, ignored)
  let names = left.keys().collect()
  names.sort()
  for name in names {
    if differences.length() >= max_differences {
      return
    }
    match right.get(name) {
      None =>
        add_difference(
          differences,
          "headers." + name,
          "missing",
          left[name].to_json(),
          Json::null(),
          "response header is missing",
        )
      Some(value) =>
        if value != left[name] {
          add_difference(
            differences,
            "headers." + name,
            "value",
            left[name].to_json(),
            value.to_json(),
            "response header changed",
          )
        }
    }
  }
  let extra = right.keys().collect()
  extra.sort()
  for name in extra {
    if differences.length() >= max_differences {
      return
    }
    if !left.contains(name) {
      add_difference(
        differences,
        "headers." + name,
        "unexpected",
        Json::null(),
        right[name].to_json(),
        "response header was added",
      )
    }
  }
}

///|
fn compare_bodies(
  expected : Json,
  actual : Json,
  differences : Array[Difference],
  max_differences : Int,
) -> String {
  let left = replay_text(expected, "body", "")
  let right = replay_text(actual, "body", "")
  if left == right {
    return "identical"
  }
  let left_json = try_parse_json(left)
  let right_json = try_parse_json(right)
  match (left_json, right_json) {
    (Some(left_value), Some(right_value)) => {
      compare_json_values(
        left_value, right_value, "$", differences, max_differences,
      )
      "json"
    }
    _ => {
      let left_lines = left.split("\n").map(x => x.to_owned()).collect()
      let right_lines = right.split("\n").map(x => x.to_owned()).collect()
      let shared = left_lines.length().min(right_lines.length())
      let mut first = -1
      for index = 0; index < shared; index = index + 1 {
        if first < 0 && left_lines[index] != right_lines[index] {
          first = index
        }
      }
      if first < 0 {
        first = shared
      }
      add_difference(
        differences,
        "body.line[" + (first + 1).to_string() + "]",
        "text",
        left_lines.get(first).unwrap_or("").to_json(),
        right_lines.get(first).unwrap_or("").to_json(),
        "response body text changed",
      )
      "text"
    }
  }
}

///|
fn diff_responses(expected : Json, actual : Json, options : Json) -> Json {
  let differences : Array[Difference] = []
  let max_differences = clamp_int(
    replay_int(options, "maxDifferences", 100),
    1,
    1000,
  )
  if replay_int(expected, "status", 0) != replay_int(actual, "status", 0) {
    add_difference(
      differences,
      "status",
      "value",
      replay_int(expected, "status", 0).to_json(),
      replay_int(actual, "status", 0).to_json(),
      "HTTP status changed",
    )
  }
  let ignored = replay_strings(options, "ignoreHeaders").map(lowercase)
  for default_name in ["date", "server", "content-length", "connection"] {
    if !ignored.contains(default_name) {
      ignored.push(default_name)
    }
  }
  compare_headers(expected, actual, ignored, differences, max_differences)
  let body_mode = if differences.length() < max_differences {
    compare_bodies(expected, actual, differences, max_differences)
  } else {
    "skipped"
  }
  {
    "equal": differences.length() == 0,
    "differenceCount": differences.length(),
    "bodyMode": body_mode,
    "truncated": differences.length() >= max_differences,
    "differences": differences.map(difference_json).to_json(),
  }
}

///|
pub fn diff_responses_json(source : String) -> String {
  try {
    let input = replay_parse(source, "response diff input")
    replay_result(
      diff_responses(
        replay_field(input, "expected"),
        replay_field(input, "actual"),
        replay_field(input, "options"),
      ),
    )
  } catch {
    error => replay_error(error.to_string())
  }
}
