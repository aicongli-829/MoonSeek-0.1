///|
let state_directory = ".filenest"

///|
async fn ensure_state(root : String) -> String {
  let state = native_path(root, state_directory)
  let history = native_path(state, "history")
  let stage = native_path(state, "stage")
  if !@fs.exists(history) {
    @fs.mkdir(history, recursive=true)
  }
  if !@fs.exists(stage) {
    @fs.mkdir(stage, recursive=true)
  }
  state
}

///|
async fn atomic_text(path : String, content : String) -> Unit {
  ensure_parent(path)
  let temporary = path + "." + operation_id() + ".tmp"
  errdefer (if @fs.exists(temporary) {
    @fs.remove(temporary) catch {
      _ => ()
    }
  })
  @fs.write_file(temporary, content, create_mode=CreateNew, sync=Full)
  @fs.rename(temporary, path, replace=true)
}

///|
async fn acquire_lock(root : String) -> String {
  let state = ensure_state(root)
  let lock_path = native_path(state, "lock")
  try {
    @fs.write_file(
      lock_path,
      ({ "created": @env.now().to_string() } : Json).stringify(),
      create_mode=CreateNew,
      sync=Full,
    )
    lock_path
  } catch {
    _ =>
      fail(
        "这个文件夹已有操作正在执行；若上次程序异常退出，请确认无进程运行后删除 .filenest/lock",
      )
  }
}

///|
async fn release_lock(path : String) -> Unit {
  if @fs.exists(path) {
    @fs.remove(path)
  }
}

///|
fn valid_operation_id(id : String) -> Bool {
  id.length() >= 16 &&
  id.length() <= 64 &&
  id.all(char => {
    char.is_ascii_digit() || (char >= 'a' && char <= 'f') || char == '-'
  })
}

///|
async fn history_documents(root : String) -> Array[Json] {
  let state = ensure_state(root)
  let directory = native_path(state, "history")
  let records : Array[Json] = []
  for name in @fs.readdir(directory, include_hidden=false, sort=true) {
    if !name.has_suffix(".json") {
      continue
    }
    records.push(
      parse_document(read_text(native_path(directory, name)), "操作记录"),
    ) catch {
      error =>
        records.push({
          "id": name,
          "status": "unreadable",
          "error": error.to_string(),
          "operations": [],
        })
    }
  }
  records
}

///|
pub async fn history_json(root_input : String) -> String {
  try {
    let root = resolve_root(root_input)
    ({ "records": history_documents(root).to_json() } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}

///|
async fn save_journal(root : String, id : String, journal : Json) -> Unit {
  let state = ensure_state(root)
  atomic_text(
    native_path(native_path(state, "history"), id + ".json"),
    journal.stringify(indent=2),
  )
}

///|
async fn read_journal(root : String, id : String) -> Json {
  guard valid_operation_id(id) else { fail("批次编号不合法") }
  let state = ensure_state(root)
  let path = native_path(native_path(state, "history"), id + ".json")
  guard @fs.exists(path) else { fail("没有找到该操作记录") }
  let journal = parse_document(read_text(path), "操作记录")
  guard json_text(journal, "id", "") == id else {
    fail("操作记录编号不匹配")
  }
  journal
}
