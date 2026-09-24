///|
priv struct ValidationIssue {
  level : String
  code : String
  path : String
  message : String
}

///|
fn validation_issue_json(issue : ValidationIssue) -> Json {
  {
    "level": issue.level,
    "code": issue.code,
    "path": issue.path,
    "message": issue.message,
  }
}

///|
fn add_issue(
  issues : Array[ValidationIssue],
  level : String,
  code : String,
  path : String,
  message : String,
) -> Unit {
  issues.push({ level, code, path, message, })
}

///|
fn validate_condition(
  condition : Json,
  path : String,
  issues : Array[ValidationIssue],
) -> Unit {
  let name = replay_text(condition, "name", "").trim().to_owned()
  if name == "" {
    add_issue(
      issues, "error", "condition.name.empty", path, "condition name is required",
    )
  }
  let operator = lowercase(replay_text(condition, "operator", "equals"))
  let allowed = [
    "present", "absent", "equals", "exact", "equals-ignore-case", "contains", "contains-ignore-case",
    "prefix", "suffix", "wildcard",
  ]
  if !allowed.contains(operator) {
    add_issue(
      issues,
      "error",
      "condition.operator.unsupported",
      path + ".operator",
      "unsupported condition operator '" + operator + "'",
    )
  }
  if ["present", "absent"].contains(operator) &&
    replay_text(condition, "value", "") != "" {
    add_issue(
      issues,
      "warning",
      "condition.value.ignored",
      path + ".value",
      "the value is ignored for presence checks",
    )
  }
}

///|
fn validate_route(
  route : Json,
  index : Int,
  issues : Array[ValidationIssue],
) -> Unit {
  let base = "routes[" + index.to_string() + "]"
  if replay_text(route, "id", "").trim() == "" {
    add_issue(
      issues,
      "error",
      "route.id.empty",
      base + ".id",
      "route id is required",
    )
  }
  if replay_text(route, "name", "").trim() == "" {
    add_issue(
      issues,
      "warning",
      "route.name.empty",
      base + ".name",
      "route name is empty",
    )
  }
  let rule = replay_field(route, "match")
  let path = replay_text(rule, "path", "")
  if path == "" || !path.has_prefix("/") {
    add_issue(
      issues,
      "error",
      "route.path.invalid",
      base + ".match.path",
      "route path must start with /",
    )
  }
  let path_mode = lowercase(replay_text(rule, "pathMode", "exact"))
  if !["exact", "prefix", "template", "wildcard"].contains(path_mode) {
    add_issue(
      issues,
      "error",
      "route.pathMode.unsupported",
      base + ".match.pathMode",
      "unsupported path mode '" + path_mode + "'",
    )
  }
  for method_index, verb in replay_strings(rule, "methods") {
    if !supported_methods.contains(uppercase(verb)) {
      add_issue(
        issues,
        "error",
        "route.method.unsupported",
        base + ".match.methods[" + method_index.to_string() + "]",
        "unsupported HTTP method '" + verb + "'",
      )
    }
  }
  for condition_index, condition in replay_array(rule, "headers") {
    validate_condition(
      condition,
      base + ".match.headers[" + condition_index.to_string() + "]",
      issues,
    )
  }
  for condition_index, condition in replay_array(rule, "query") {
    validate_condition(
      condition,
      base + ".match.query[" + condition_index.to_string() + "]",
      issues,
    )
  }
  let body = replay_field(rule, "body")
  let body_mode = lowercase(replay_text(body, "mode", "any"))
  if !["any", "empty", "exact", "contains", "json", "json-exact", "json-subset"].contains(
      body_mode,
    ) {
    add_issue(
      issues,
      "error",
      "route.body.mode.unsupported",
      base + ".match.body.mode",
      "unsupported body mode '" + body_mode + "'",
    )
  }
  if ["json", "json-exact", "json-subset"].contains(body_mode) {
    match try_parse_json(replay_text(body, "value", "")) {
      Some(_) => ()
      None =>
        add_issue(
          issues,
          "error",
          "route.body.json.invalid",
          base + ".match.body.value",
          "expected body is not valid JSON",
        )
    }
  }
  let response = replay_field(route, "response")
  let status = replay_int(response, "status", 200)
  if status < 100 || status > 599 {
    add_issue(
      issues,
      "error",
      "response.status.invalid",
      base + ".response.status",
      "status must be between 100 and 599",
    )
  }
  let delay = replay_int(response, "delayMs", 0)
  if delay < 0 || delay > 30000 {
    add_issue(
      issues,
      "error",
      "response.delay.invalid",
      base + ".response.delayMs",
      "delay must be between 0 and 30000 milliseconds",
    )
  }
  let header_names : Map[String, Bool] = Map([])
  for header_index, header in replay_array(response, "headers") {
    let name = lowercase(replay_text(header, "name", ""))
    let header_path = base +
      ".response.headers[" +
      header_index.to_string() +
      "]"
    if name == "" {
      add_issue(
        issues, "error", "response.header.name.empty", header_path, "header name is required",
      )
    } else if header_names.contains(name) {
      add_issue(
        issues,
        "warning",
        "response.header.duplicate",
        header_path,
        "duplicate response header '" + name + "'",
      )
    }
    header_names[name] = true
  }
}

///|
fn validate_workspace(workspace : Json) -> Json {
  let issues : Array[ValidationIssue] = []
  let version = replay_int(workspace, "formatVersion", -1)
  if version != 1 {
    add_issue(
      issues, "error", "workspace.version.unsupported", "formatVersion", "only workspace format version 1 is supported",
    )
  }
  let ids : Map[String, Int] = Map([])
  let routes = replay_array(workspace, "routes")
  for index, route in routes {
    validate_route(route, index, issues)
    let id = replay_text(route, "id", "")
    if id != "" {
      match ids.get(id) {
        Some(first) =>
          add_issue(
            issues,
            "error",
            "route.id.duplicate",
            "routes[" + index.to_string() + "].id",
            "route id duplicates routes[" + first.to_string() + "]",
          )
        None => ids[id] = index
      }
    }
  }
  let errors = issues.filter(issue => issue.level == "error").length()
  let warnings = issues.filter(issue => issue.level == "warning").length()
  {
    "valid": errors == 0,
    "errors": errors,
    "warnings": warnings,
    "routeCount": routes.length(),
    "issues": issues.map(validation_issue_json).to_json(),
  }
}

///|
pub fn validate_workspace_json(source : String) -> String {
  replay_result(validate_workspace(replay_parse(source, "workspace"))) catch {
    error => replay_error(error.to_string())
  }
}
