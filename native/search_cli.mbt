///|
let search_cli_help =
  #|MoonSeek · fast local filename and full-text search
  #|
  #|Usage:
  #|  moonseek index add <folder> [--database path] [--ext md,txt,mbt]
  #|  moonseek index remove <folder> [--database path]
  #|  moonseek search <query> [--database path] [--limit 50]
  #|  moonseek suggest <prefix> [--database path] [--limit 12]
  #|  moonseek status [--database path]
  #|  moonseek doctor [--database path]
  #|  moonseek serve [--database path] [--port 4173]
  #|
  #|Query filters:
  #|  ext:md,mbt    restrict file extensions
  #|  path:docs     restrict relative paths
  #|  root:notes    restrict indexed roots
  #|  -draft        exclude a term
  #|  "exact words" boost an exact phrase

///|
fn search_argument_after(args : Array[String], flag : String) -> String? {
  for index, value in args {
    if value == flag && index + 1 < args.length() {
      return Some(args[index + 1])
    }
  }
  None
}

///|
fn search_database_argument(args : Array[String]) -> String {
  search_argument_after(args, "--database").unwrap_or(".moonseek/index.json")
}

///|
fn search_query_from_arguments(args : Array[String], start : Int) -> String {
  let pieces : Array[String] = []
  let mut index = start
  while index < args.length() {
    let value = args[index]
    if value == "--database" || value == "--limit" {
      index = index + 2
    } else {
      pieces.push(value)
      index = index + 1
    }
  }
  pieces.join(" ")
}

///|
fn search_cli_extensions(args : Array[String]) -> Array[String] {
  let result : Array[String] = []
  match search_argument_after(args, "--ext") {
    None => ()
    Some(source) =>
      for piece in source.split(",") {
        let clean = piece.trim().trim_start(chars=['.']).to_owned().to_lower()
        if clean != "" {
          result.push(clean)
        }
      }
  }
  result
}

///|
fn search_print_result(source : String) -> Unit raise {
  let document = parse_document(source, "command result")
  match json_field(document, "error") {
    String(message) => fail(message)
    _ => println(document.stringify(indent=2))
  }
}

///|
pub async fn run_search_cli(args : Array[String]) -> Unit {
  if args.contains("--version") {
    println("MoonSeek 0.1.0 · MoonBit Native")
    return
  }
  let mut command_index : Int? = None
  let mut command = ""
  for index, value in args {
    if command_index is None &&
      ["index", "search", "suggest", "status", "doctor", "serve"].contains(
        value,
      ) {
      command_index = Some(index)
      command = value
    }
  }
  let index = match command_index {
    Some(value) => value
    None => {
      println(search_cli_help)
      return
    }
  }
  let database = search_database_argument(args)
  match command {
    "status" => search_print_result(search_status_json(database))
    "doctor" => search_print_result(diagnose_search_index_json(database))
    "search" => {
      guard index + 1 < args.length() else { fail("search requires a query") }
      let limit = match search_argument_after(args, "--limit") {
        Some(value) =>
          @string.parse_int(value) catch {
            _ => fail("invalid --limit")
          }
        None => 50
      }
      let query = search_query_from_arguments(args, index + 1)
      guard query != "" else { fail("search requires a query") }
      search_print_result(run_search_json(database, query, limit~))
    }
    "suggest" => {
      guard index + 1 < args.length() else { fail("suggest requires a prefix") }
      let limit = match search_argument_after(args, "--limit") {
        Some(value) =>
          @string.parse_int(value) catch {
            _ => fail("invalid --limit")
          }
        None => 12
      }
      search_print_result(
        suggest_from_index_json(database, args[index + 1], limit~),
      )
    }
    "index" => {
      guard index + 2 < args.length() else {
        fail("index requires add/remove and a folder")
      }
      match args[index + 1] {
        "add" =>
          search_print_result(
            rebuild_search_index_json(
              database,
              args[index + 2],
              options_source=(
                { "extensions": search_cli_extensions(args).to_json() } : Json).stringify(),
            ),
          )
        "remove" =>
          search_print_result(
            remove_search_root_json(database, args[index + 2]),
          )
        _ => fail("index action must be add or remove")
      }
    }
    "serve" => {
      let port = match search_argument_after(args, "--port") {
        Some(value) =>
          @string.parse_int(value) catch {
            _ => fail("invalid --port")
          }
        None => 4173
      }
      guard port >= 1024 && port <= 65535 else {
        fail("port must be 1024-65535")
      }
      serve_search(database, port)
    }
    _ => fail("unknown command")
  }
}
