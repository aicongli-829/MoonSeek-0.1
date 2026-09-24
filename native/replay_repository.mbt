///|
fn empty_workspace() -> Json {
  {
    "formatVersion": 1,
    "name": "MoonReplay Workspace",
    "settings": {
      "historyLimit": 2000,
      "maxBodyBytes": 1048576,
      "redaction": {
        "headers": [],
        "query": [],
        "jsonFields": [],
        "replacement": "[REDACTED]",
      },
    },
    "routes": [],
  }
}

///|
fn empty_history() -> Json {
  { "formatVersion": 1, "nextSequence": "1", "exchanges": [] }
}

///|
async fn atomic_write_json(path : String, value : Json) -> Unit {
  ensure_parent(path)
  let temporary = path + "." + operation_id() + ".tmp"
  errdefer (if @fs.exists(temporary) {
    @fs.remove(temporary) catch {
      _ => ()
    }
  })
  @fs.write_file(
    temporary,
    value.stringify(indent=2) + "\n",
    create_mode=CreateNew,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
async fn load_json_file(path : String, fallback : Json, label : String) -> Json {
  if !@fs.exists(path) {
    return fallback
  }
  parse_document(read_text(path), label)
}

///|
pub async fn load_workspace(path : String) -> Json {
  load_json_file(path, empty_workspace(), "workspace")
}

///|
pub async fn save_workspace(path : String, workspace : Json) -> Unit {
  let report = parse_document(
    @core.validate_workspace_json(workspace.stringify()),
    "validation report",
  )
  match json_field(report, "error") {
    String(message) => fail(message)
    _ => ()
  }
  guard json_bool(report, "valid", false) else {
    fail("workspace validation failed: " + report.stringify())
  }
  atomic_write_json(path, workspace)
}

///|
pub async fn workspace_status_json(path : String) -> String {
  try {
    let workspace = load_workspace(path)
    let report = parse_document(
      @core.validate_workspace_json(workspace.stringify()),
      "validation report",
    )
    (
      {
        "workspace": path,
        "name": json_text(workspace, "name", "MoonReplay Workspace"),
        "routeCount": json_array(workspace, "routes").length(),
        "validation": report,
      } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}

///|
pub async fn initialize_workspace_json(
  path : String,
  force? : Bool = false,
) -> String {
  try {
    guard force || !@fs.exists(path) else {
      fail("workspace already exists; use --force to replace it")
    }
    let workspace = empty_workspace()
    save_workspace(path, workspace)
    ({ "workspace": path, "created": true, "document": workspace } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}

///|
fn route_index(routes : Array[Json], id : String) -> Int? {
  for index, route in routes {
    if json_text(route, "id", "") == id {
      return Some(index)
    }
  }
  None
}

///|
pub async fn upsert_route_json(path : String, route_source : String) -> String {
  try {
    let workspace = load_workspace(path)
    let route = parse_document(route_source, "route")
    let id = json_text(route, "id", "").trim().to_owned()
    guard id != "" else { fail("route id is required") }
    let routes = json_array(workspace, "routes")
    let created = match route_index(routes, id) {
      Some(index) => {
        routes[index] = route
        false
      }
      None => {
        routes.push(route)
        true
      }
    }
    let updated : Json = match workspace {
      Object(fields) => {
        fields["routes"] = routes.to_json()
        Json::object(fields)
      }
      _ => fail("workspace must be a JSON object")
    }
    save_workspace(path, updated)
    (
      {
        "workspace": path,
        "created": created,
        "route": route,
        "routeCount": routes.length(),
      } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}

///|
pub async fn remove_route_json(path : String, id : String) -> String {
  try {
    let workspace = load_workspace(path)
    let routes = json_array(workspace, "routes")
    let kept = routes.filter(route => json_text(route, "id", "") != id)
    guard kept.length() != routes.length() else { fail("route does not exist") }
    let updated : Json = match workspace {
      Object(fields) => {
        fields["routes"] = kept.to_json()
        Json::object(fields)
      }
      _ => fail("workspace must be a JSON object")
    }
    save_workspace(path, updated)
    ({ "workspace": path, "removed": id, "routeCount": kept.length() } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}

///|
pub async fn list_routes_json(path : String) -> String {
  try {
    let workspace = load_workspace(path)
    ({ "routes": json_field(workspace, "routes") } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}

///|
async fn load_history(path : String) -> Json {
  load_json_file(path, empty_history(), "request history")
}

///|
fn next_sequence(history : Json) -> Int64 {
  json_int64_or(history, "nextSequence", 1L).max(1L)
}

///|
pub async fn append_exchange(
  path : String,
  exchange : Json,
  limit? : Int = 2000,
) -> Json {
  let history = load_history(path)
  let sequence = next_sequence(history)
  let rows = json_array(history, "exchanges")
  let recorded : Json = match exchange {
    Object(fields) => {
      fields["sequence"] = Json::string(sequence.to_string())
      Json::object(fields)
    }
    _ => fail("exchange must be a JSON object")
  }
  rows.push(recorded)
  let bounded = if rows.length() > limit {
    rows[rows.length() - limit:].to_owned()
  } else {
    rows
  }
  atomic_write_json(path, {
    "formatVersion": 1,
    "nextSequence": (sequence + 1L).to_string(),
    "exchanges": bounded.to_json(),
  })
  recorded
}

///|
pub async fn get_exchange_json(path : String, id : String) -> String {
  try {
    let history = load_history(path)
    for exchange in json_array(history, "exchanges") {
      if json_text(exchange, "id", "") == id {
        return ({ "exchange": exchange } : Json).stringify()
      }
    }
    fail("exchange does not exist")
  } catch {
    error => json_error(error.to_string())
  }
}

///|
pub async fn list_exchanges_json(
  path : String,
  filter_source? : String = "{}",
) -> String {
  try {
    let history = load_history(path)
    let filter = parse_document(filter_source, "history filter")
    @core.filter_exchanges_json(
      (
        {
          "exchanges": json_field(history, "exchanges"),
          "filter": json_field(filter, "filter"),
          "offset": json_int64_or(filter, "offset", 0L).to_int(),
          "limit": json_int64_or(filter, "limit", 50L).to_int(),
        } : Json).stringify(),
    )
  } catch {
    error => json_error(error.to_string())
  }
}

///|
pub async fn clear_history_json(path : String) -> String {
  try {
    let previous = load_history(path)
    let count = json_array(previous, "exchanges").length()
    atomic_write_json(path, empty_history())
    ({ "history": path, "removed": count } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}
