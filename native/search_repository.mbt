///|
fn empty_search_index() -> Json {
  {
    "formatVersion": 1,
    "created": "",
    "documents": [],
    "terms": [],
    "statistics": {
      "documents": 0,
      "terms": 0,
      "tokens": 0,
      "averageDocumentTokens": "0",
    },
  }
}

///|
async fn load_search_index(path : String) -> Json {
  if !@fs.exists(path) {
    return empty_search_index()
  }
  parse_document(read_text(path), "search index")
}

///|
async fn save_search_index(path : String, index : Json) -> Unit {
  ensure_parent(path)
  let temporary = path + "." + operation_id() + ".tmp"
  errdefer (if @fs.exists(temporary) {
    @fs.remove(temporary) catch {
      _ => ()
    }
  })
  @fs.write_file(temporary, index.stringify(), create_mode=CreateNew, sync=Full)
  @fs.rename(temporary, path, replace=true)
}

///|
fn search_index_roots(index : Json) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let roots : Array[String] = []
  for document in previous_documents(index) {
    let root = json_text(document, "root", "")
    if root != "" && !seen.contains(root) {
      seen[root] = true
      roots.push(root)
    }
  }
  roots.sort()
  roots
}

///|
pub async fn search_status_json(database : String) -> String {
  try {
    let index = load_search_index(database)
    (
      {
        "database": database,
        "roots": search_index_roots(index).to_json(),
        "statistics": json_field(index, "statistics"),
        "created": json_text(index, "created", ""),
      } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}

///|
pub async fn rebuild_search_index_json(
  database : String,
  root : String,
  options_source? : String = "{}",
) -> String {
  try {
    let previous = load_search_index(database)
    let options = parse_document(options_source, "index options")
    let scanned = scan_search_documents(root, previous, options)
    let built_source = @core.build_search_index_json(
      (
        {
          "created": @env.now().to_string(),
          "documents": json_field(scanned, "documents"),
        } : Json).stringify(),
    )
    let built = parse_document(built_source, "built index")
    match json_field(built, "error") {
      String(message) => fail(message)
      _ => ()
    }
    save_search_index(database, built)
    (
      {
        "database": database,
        "root": json_text(scanned, "root", ""),
        "scan": json_field(scanned, "scan"),
        "statistics": json_field(built, "statistics"),
        "roots": search_index_roots(built).to_json(),
      } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}

///|
pub async fn remove_search_root_json(
  database : String,
  root_input : String,
) -> String {
  try {
    let root = resolve_search_root(root_input)
    let previous = load_search_index(database)
    let kept = previous_documents(previous).filter(document => {
      json_text(document, "root", "") != root
    })
    let built = parse_document(
      @core.build_search_index_json(
        (
          { "created": @env.now().to_string(), "documents": kept.to_json() } :
          Json).stringify(),
      ),
      "built index",
    )
    save_search_index(database, built)
    (
      {
        "database": database,
        "removedRoot": root,
        "statistics": json_field(built, "statistics"),
        "roots": search_index_roots(built).to_json(),
      } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}

///|
pub async fn run_search_json(
  database : String,
  query : String,
  limit? : Int = 50,
) -> String {
  try {
    let index = load_search_index(database)
    @core.search_index_json(
      ({ "index": index, "query": query, "limit": limit } : Json).stringify(),
    )
  } catch {
    error => json_error(error.to_string())
  }
}

///|
pub async fn suggest_from_index_json(
  database : String,
  prefix : String,
  limit? : Int = 12,
) -> String {
  try {
    let index = load_search_index(database)
    @core.suggest_search_json(
      ({ "index": index, "prefix": prefix, "limit": limit } : Json).stringify(),
    )
  } catch {
    error => json_error(error.to_string())
  }
}

///|
pub async fn diagnose_search_index_json(database : String) -> String {
  try {
    let index = load_search_index(database)
    let report = parse_document(
      @core.validate_search_index_json(index.stringify()),
      "diagnostic report",
    )
    match json_field(report, "error") {
      String(message) => fail(message)
      _ => ({ "database": database, "report": report } : Json).stringify()
    }
  } catch {
    error => json_error(error.to_string())
  }
}
