///|
fn test_json(source : String) -> Json raise {
  @json.parse(source) catch {
    _ => fail("expected a JSON response")
  }
}

///|
fn test_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn test_array(value : Json, key : String) -> Array[Json] {
  match test_field(value, key) {
    Array(items) => items
    _ => []
  }
}

///|
fn test_int(value : Json, key : String) -> Int {
  match test_field(value, key) {
    Number(number, ..) => number.to_int()
    String(text) => @string.parse_int(text) catch { _ => -1 }
    _ => -1
  }
}

///|
fn test_text(value : Json, key : String) -> String {
  match test_field(value, key) {
    String(text) => text
    _ => ""
  }
}

///|
async test "native index includes names for every file and text contents" {
  let root = @fs.tmpdir(prefix="moonseek-index-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.mkdir(root + "/notes")
  @fs.write_file(
    root + "/notes/roadmap.md",
    "MoonSeek provides instant local search.",
    create_mode=CreateNew,
  )
  @fs.write_file(
    root + "/summer-photo.png",
    b"\x89PNG\r\n\x1a\n",
    create_mode=CreateNew,
  )
  let database = root + "/.moonseek/index.json"
  let indexed = test_json(rebuild_search_index_json(database, root))
  let scan = test_field(indexed, "scan")
  assert_eq(test_int(scan, "indexed"), 2)
  assert_eq(test_int(scan, "contentFiles"), 1)
  assert_eq(test_int(scan, "metadataFiles"), 1)
  let content_search = test_json(run_search_json(database, "instant", limit=10))
  let content_rows = test_array(content_search, "results")
  assert_eq(content_rows.length(), 1)
  assert_eq(test_text(content_rows[0], "name"), "roadmap.md")
  let image_search = test_json(
    run_search_json(database, "summer photo", limit=10),
  )
  let image_rows = test_array(image_search, "results")
  assert_eq(image_rows.length(), 1)
  assert_eq(test_text(image_rows[0], "category"), "image")
  @fs.rmdir(root, recursive=true)
}

///|
async test "incremental indexing reuses unchanged documents" {
  let root = @fs.tmpdir(prefix="moonseek-incremental-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.write_file(root + "/alpha.txt", "alpha", create_mode=CreateNew)
  @fs.write_file(root + "/beta.txt", "beta", create_mode=CreateNew)
  let database = root + "/.moonseek/index.json"
  ignore(rebuild_search_index_json(database, root))
  let second = test_json(rebuild_search_index_json(database, root))
  let scan = test_field(second, "scan")
  assert_eq(test_int(scan, "indexed"), 0)
  assert_eq(test_int(scan, "reused"), 2)
  @fs.rmdir(root, recursive=true)
}

///|
async test "search filters by category extension path and size" {
  let root = @fs.tmpdir(prefix="moonseek-filters-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.mkdir(root + "/src")
  @fs.mkdir(root + "/docs")
  @fs.write_file(
    root + "/src/search.mbt",
    "pub fn search() -> Unit {}",
    create_mode=CreateNew,
  )
  @fs.write_file(
    root + "/docs/search.md",
    "Search documentation",
    create_mode=CreateNew,
  )
  let database = root + "/.moonseek/index.json"
  ignore(rebuild_search_index_json(database, root))
  let code = test_json(run_search_json(database, "search type:code", limit=10))
  assert_eq(test_array(code, "results").length(), 1)
  assert_eq(test_text(test_array(code, "results")[0], "extension"), "mbt")
  let docs = test_json(
    run_search_json(database, "search ext:md path:docs size:<1kb", limit=10),
  )
  assert_eq(test_array(docs, "results").length(), 1)
  assert_eq(test_text(test_array(docs, "results")[0], "extension"), "md")
  @fs.rmdir(root, recursive=true)
}

///|
async test "removing one root preserves documents from another root" {
  let first = @fs.tmpdir(prefix="moonseek-root-one-")
  let second = @fs.tmpdir(prefix="moonseek-root-two-")
  let state = @fs.tmpdir(prefix="moonseek-state-")
  errdefer (@fs.rmdir(first, recursive=true) catch { _ => () })
  errdefer (@fs.rmdir(second, recursive=true) catch { _ => () })
  errdefer (@fs.rmdir(state, recursive=true) catch { _ => () })
  @fs.write_file(first + "/first.txt", "one", create_mode=CreateNew)
  @fs.write_file(second + "/second.txt", "two", create_mode=CreateNew)
  let database = state + "/index.json"
  ignore(rebuild_search_index_json(database, first))
  ignore(rebuild_search_index_json(database, second))
  let before = test_json(search_status_json(database))
  assert_eq(test_array(before, "roots").length(), 2)
  ignore(remove_search_root_json(database, first))
  let after = test_json(search_status_json(database))
  assert_eq(test_array(after, "roots").length(), 1)
  let result = test_json(run_search_json(database, "second", limit=10))
  assert_eq(test_array(result, "results").length(), 1)
  @fs.rmdir(first, recursive=true)
  @fs.rmdir(second, recursive=true)
  @fs.rmdir(state, recursive=true)
}

///|
async test "moonseekignore excludes patterns and honors a later exception" {
  let root = @fs.tmpdir(prefix="moonseek-ignore-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.write_file(
    root + "/.moonseekignore",
    "*.log\n!important.log\n",
    create_mode=CreateNew,
  )
  @fs.write_file(root + "/debug.log", "hidden debug", create_mode=CreateNew)
  @fs.write_file(
    root + "/important.log",
    "retained event",
    create_mode=CreateNew,
  )
  @fs.write_file(root + "/readme.txt", "visible note", create_mode=CreateNew)
  let database = root + "/.moonseek/index.json"
  let indexed = test_json(rebuild_search_index_json(database, root))
  let statistics = test_field(indexed, "statistics")
  assert_eq(test_int(statistics, "documents"), 2)
  let hidden = test_json(run_search_json(database, "debug", limit=10))
  assert_eq(test_array(hidden, "results").length(), 0)
  let retained = test_json(run_search_json(database, "retained", limit=10))
  assert_eq(test_array(retained, "results").length(), 1)
  @fs.rmdir(root, recursive=true)
}

///|
async test "doctor validates the persisted index and suggestions use it" {
  let root = @fs.tmpdir(prefix="moonseek-doctor-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.write_file(
    root + "/moonseek-guide.md",
    "Fast filename search",
    create_mode=CreateNew,
  )
  let database = root + "/.moonseek/index.json"
  ignore(rebuild_search_index_json(database, root))
  let diagnosed = test_json(diagnose_search_index_json(database))
  let report = test_field(diagnosed, "report")
  match test_field(report, "valid") {
    true => ()
    _ => fail("persisted index should pass diagnostics")
  }
  let suggested = test_json(suggest_from_index_json(database, "moon", limit=10))
  let rows = test_array(suggested, "suggestions")
  assert_true(rows.length() > 0)
  assert_true(rows.any(row => test_text(row, "value").contains("moonseek")))
  @fs.rmdir(root, recursive=true)
}
