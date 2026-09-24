///|
let replay_cli_help =
  #|MoonReplay · local HTTP capture, mock, replay, and diff workbench
  #|
  #|Usage:
  #|  moonreplay init [--workspace path] [--force]
  #|  moonreplay serve [--workspace path] [--history path] [--port 4173]
  #|  moonreplay routes list [--workspace path]
  #|  moonreplay routes add <route.json> [--workspace path]
  #|  moonreplay routes remove <route-id> [--workspace path]
  #|  moonreplay history list [--history path] [--method POST] [--status 5xx]
  #|  moonreplay history show <exchange-id> [--history path]
  #|  moonreplay history clear [--history path]
  #|  moonreplay replay <exchange-id> <target-url> [--history path]
  #|  moonreplay curl <exchange-id> [--history path] [--base-url url]
  #|  moonreplay validate [--workspace path]
  #|
  #|Defaults:
  #|  workspace  .moonreplay/workspace.json
  #|  history    .moonreplay/history.json
  #|  port       4173

///|
fn cli_argument_after(args : Array[String], flag : String) -> String? {
  for index, value in args {
    if value == flag && index + 1 < args.length() {
      return Some(args[index + 1])
    }
  }
  None
}

///|
fn cli_workspace(args : Array[String]) -> String {
  cli_argument_after(args, "--workspace").unwrap_or(
    ".moonreplay/workspace.json",
  )
}

///|
fn cli_history(args : Array[String]) -> String {
  cli_argument_after(args, "--history").unwrap_or(".moonreplay/history.json")
}

///|
fn cli_port(args : Array[String]) -> Int raise {
  let port = match cli_argument_after(args, "--port") {
    Some(value) =>
      @string.parse_int(value) catch {
        _ => fail("invalid --port")
      }
    None => 4173
  }
  guard port >= 1024 && port <= 65535 else {
    fail("port must be between 1024 and 65535")
  }
  port
}

///|
fn cli_print_json(source : String) -> Unit raise {
  let document = parse_document(source, "command result")
  match json_field(document, "error") {
    String(message) => fail(message)
    _ => println(document.stringify(indent=2))
  }
}

///|
fn first_command(args : Array[String]) -> (Int, String)? {
  let commands = [
    "init", "serve", "routes", "history", "replay", "curl", "validate",
  ]
  for index, value in args {
    if commands.contains(value) {
      return Some((index, value))
    }
  }
  None
}

///|
fn history_filter_from_args(args : Array[String]) -> Json {
  let methods = match cli_argument_after(args, "--method") {
    Some(value) => [value]
    None => []
  }
  let statuses = match cli_argument_after(args, "--status") {
    Some(value) => [value]
    None => []
  }
  let path = cli_argument_after(args, "--path").unwrap_or("")
  let tag = cli_argument_after(args, "--tag")
  let limit = match cli_argument_after(args, "--limit") {
    Some(value) => @string.parse_int(value) catch { _ => 50 }
    None => 50
  }
  {
    "filter": {
      "methods": methods,
      "statuses": statuses,
      "path": path,
      "pathMode": "contains",
      "tags": match tag {
        Some(value) => [value]
        None => []
      },
    },
    "limit": limit.max(1).min(500),
  }
}

///|
async fn run_routes_command(
  args : Array[String],
  index : Int,
  workspace : String,
) -> Unit {
  guard index + 1 < args.length() else { fail("routes requires an action") }
  match args[index + 1] {
    "list" => cli_print_json(list_routes_json(workspace))
    "add" => {
      guard index + 2 < args.length() else {
        fail("routes add requires a JSON file")
      }
      cli_print_json(upsert_route_json(workspace, read_text(args[index + 2])))
    }
    "remove" => {
      guard index + 2 < args.length() else {
        fail("routes remove requires a route id")
      }
      cli_print_json(remove_route_json(workspace, args[index + 2]))
    }
    _ => fail("routes action must be list, add, or remove")
  }
}

///|
async fn run_history_command(
  args : Array[String],
  index : Int,
  history : String,
) -> Unit {
  guard index + 1 < args.length() else { fail("history requires an action") }
  match args[index + 1] {
    "list" =>
      cli_print_json(
        list_exchanges_json(
          history,
          filter_source=history_filter_from_args(args).stringify(),
        ),
      )
    "show" => {
      guard index + 2 < args.length() else {
        fail("history show requires an exchange id")
      }
      cli_print_json(get_exchange_json(history, args[index + 2]))
    }
    "clear" => cli_print_json(clear_history_json(history))
    _ => fail("history action must be list, show, or clear")
  }
}

///|
async fn curl_exchange(
  history : String,
  id : String,
  base_url : String,
) -> String {
  let loaded = parse_document(get_exchange_json(history, id), "exchange lookup")
  match json_field(loaded, "error") {
    String(message) => fail(message)
    _ => ()
  }
  @core.export_curl_json(
    (
      {
        "baseUrl": base_url,
        "request": json_field(json_field(loaded, "exchange"), "request"),
      } : Json).stringify(),
  )
}

///|
pub async fn run_replay_cli(args : Array[String]) -> Unit {
  if args.contains("--version") {
    println("MoonReplay 0.1.0 · MoonBit Native")
    return
  }
  let (index, command) = match first_command(args) {
    Some(found) => found
    None => {
      println(replay_cli_help)
      return
    }
  }
  let workspace = cli_workspace(args)
  let history = cli_history(args)
  match command {
    "init" =>
      cli_print_json(
        initialize_workspace_json(workspace, force=args.contains("--force")),
      )
    "serve" => serve_replay(workspace, history, cli_port(args))
    "routes" => run_routes_command(args, index, workspace)
    "history" => run_history_command(args, index, history)
    "validate" => cli_print_json(workspace_status_json(workspace))
    "replay" => {
      guard index + 2 < args.length() else {
        fail("replay requires an exchange id and target URL")
      }
      cli_print_json(
        replay_exchange_json(history, args[index + 1], args[index + 2]),
      )
    }
    "curl" => {
      guard index + 1 < args.length() else {
        fail("curl requires an exchange id")
      }
      let base_url = cli_argument_after(args, "--base-url").unwrap_or(
        "http://127.0.0.1:4173",
      )
      cli_print_json(curl_exchange(history, args[index + 1], base_url))
    }
    _ => fail("unknown command")
  }
}
