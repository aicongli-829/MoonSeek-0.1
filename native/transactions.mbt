///|
priv struct Fingerprint {
  size : Int64
  modified_seconds : Int64
  modified_nanos : Int
  sha256 : String
}

///|
priv struct NativeOperation {
  source : String
  target : String
  stage : String
  mut phase : String
  fingerprint : Fingerprint
}

///|
fn json_int64(value : Json, key : String) -> Int64 {
  match json_field(value, key) {
    Number(number, ..) => Int64::from_int(number.to_int())
    String(text) => @string.parse_int64(text) catch { _ => 0L }
    _ => 0L
  }
}

///|
fn fingerprint_from(value : Json) -> Fingerprint {
  {
    size: json_int64(value, "size"),
    modified_seconds: json_int64(value, "mtimeSeconds"),
    modified_nanos: match json_field(value, "mtimeNanos") {
      Number(number, ..) => number.to_int()
      _ => 0
    },
    sha256: json_text(value, "sha256", ""),
  }
}

///|
fn fingerprint_json(value : Fingerprint) -> Json {
  {
    "size": value.size.to_string(),
    "mtimeSeconds": value.modified_seconds.to_string(),
    "mtimeNanos": value.modified_nanos,
    "sha256": value.sha256,
  }
}

///|
fn operation_json(value : NativeOperation) -> Json {
  {
    "source": value.source,
    "target": value.target,
    "stage": value.stage,
    "phase": value.phase,
    "fingerprint": fingerprint_json(value.fingerprint),
  }
}

///|
fn operation_from(value : Json) -> NativeOperation {
  {
    source: json_text(value, "source", ""),
    target: json_text(value, "target", ""),
    stage: json_text(value, "stage", ""),
    phase: json_text(value, "phase", "pending"),
    fingerprint: fingerprint_from(json_field(value, "fingerprint")),
  }
}

///|
fn journal_json(
  id : String,
  created : String,
  status : String,
  operations : Array[NativeOperation],
  error : String?,
) -> Json {
  {
    "id": id,
    "created": created,
    "status": status,
    "operations": operations.map(operation_json).to_json(),
    "error": match error {
      Some(message) => message.to_json()
      None => Json::null()
    },
  }
}

///|
async fn verify_fingerprint(path : String, expected : Fingerprint) -> Unit {
  guard @fs.exists(path) else { fail("文件不存在：" + path) }
  guard @fs.kind(path, follow_symlink=false) == Regular else {
    fail("只处理普通文件")
  }
  let size = @fs.file_size(path)
  let (seconds, nanos) = @fs.mtime(path, follow_symlink=false)
  guard size == expected.size &&
    seconds == expected.modified_seconds &&
    nanos == expected.modified_nanos else {
    fail("文件已改变，请重新扫描或人工检查")
  }
  guard sha256(@fs.read_file(path).binary()) == expected.sha256 else {
    fail("文件内容已改变，请重新扫描或人工检查")
  }
}

///|
async fn move_exclusive(
  root : String,
  from : String,
  to : String,
  expected : Fingerprint,
) -> Unit {
  let source = safe_native_path(root, from, internal=true)
  let target = safe_native_path(root, to, internal=true)
  verify_fingerprint(source, expected)
  guard !@fs.exists(target) else { fail("目标已存在：" + to) }
  ensure_parent(target)
  @fs.rename(source, target, replace=false)
  verify_fingerprint(target, expected)
}

///|
fn inventory_fingerprints(inventory : Json) -> Map[String, Fingerprint] {
  let values : Map[String, Fingerprint] = Map([])
  for file in json_array(inventory, "files") {
    let path = json_text(file, "path", "")
    if path != "" {
      values[path] = fingerprint_from(json_field(file, "fingerprint"))
    }
  }
  values
}

///|
fn prepare_operations(
  id : String,
  plan : Json,
  inventory : Json,
  history : Array[Json],
) -> Array[NativeOperation] raise {
  let files = inventory_fingerprints(inventory)
  let scanned = files.keys().to_array()
  let statuses = history.map(record => json_text(record, "status", ""))
  let request : Json = {
    "id": id,
    "plan": json_array(plan, "rows").to_json(),
    "scanned": scanned.to_json(),
    "historyStatuses": statuses.to_json(),
  }
  let response = parse_document(
    @core.transaction_prepare_json(request.stringify()),
    "事务计划",
  )
  match json_field(response, "error") {
    String(message) => fail(message)
    _ => ()
  }
  json_array(response, "operations").map(raw => {
    let source = json_text(raw, "source", "")
    let fingerprint = files
      .get(source)
      .unwrap_or_else(() => fail("扫描指纹缺失：" + source))
    {
      source,
      target: json_text(raw, "target", ""),
      stage: json_text(raw, "stage", ""),
      phase: json_text(raw, "phase", "pending"),
      fingerprint,
    }
  })
}

///|
/// Execute a reviewed plan through two non-overwriting rename phases. Every
/// completed rename is followed by a synced journal update before proceeding.
pub async fn execute_json(
  root_input : String,
  plan_source : String,
  inventory_source : String,
) -> String {
  let mut lock_path = ""
  try {
    let root = resolve_root(root_input)
    lock_path = acquire_lock(root)
    let plan = parse_document(plan_source, "整理计划")
    let inventory = parse_document(inventory_source, "扫描结果")
    let id = operation_id()
    let created = @env.now().to_string()
    let operations = prepare_operations(
      id,
      plan,
      inventory,
      history_documents(root),
    )
    for operation in operations {
      ignore(safe_native_path(root, operation.source))
      ignore(safe_native_path(root, operation.target))
      verify_fingerprint(
        native_path(root, operation.source),
        operation.fingerprint,
      )
      if @fs.exists(native_path(root, operation.target)) &&
        !operations.any(item => item.source == operation.target) {
        fail("目标已存在：" + operation.target)
      }
    }
    save_journal(
      root,
      id,
      journal_json(id, created, "running", operations, None),
    )
    for operation in operations {
      move_exclusive(
        root,
        operation.source,
        operation.stage,
        operation.fingerprint,
      )
      operation.phase = "staged"
      save_journal(
        root,
        id,
        journal_json(id, created, "running", operations, None),
      )
    }
    for operation in operations {
      operation.phase = "applying"
      save_journal(
        root,
        id,
        journal_json(id, created, "running", operations, None),
      )
      move_exclusive(
        root,
        operation.stage,
        operation.target,
        operation.fingerprint,
      )
      operation.phase = "done"
      save_journal(
        root,
        id,
        journal_json(id, created, "running", operations, None),
      )
    }
    let journal = journal_json(id, created, "completed", operations, None)
    save_journal(root, id, journal)
    release_lock(lock_path)
    lock_path = ""
    journal.stringify()
  } catch {
    error => {
      if lock_path != "" {
        release_lock(lock_path) catch {
          _ => ()
        }
      }
      json_error(error.to_string())
    }
  }
}

///|
fn current_location(operation : NativeOperation) -> String? {
  match operation.phase {
    "pending" | "restored" => Some(operation.source)
    "staged" | "applying" | "undo-staged" | "restoring" => Some(operation.stage)
    "done" | "undo-staging" => Some(operation.target)
    _ => None
  }
}

///|
/// Undo first moves every completed destination back into its private stage,
/// then restores original paths. This handles rename cycles without overwrites.
pub async fn undo_json(root_input : String, id : String) -> String {
  let mut lock_path = ""
  try {
    let root = resolve_root(root_input)
    lock_path = acquire_lock(root)
    let saved = read_journal(root, id)
    if json_text(saved, "status", "") == "undone" {
      release_lock(lock_path)
      return saved.stringify()
    }
    let created = json_text(saved, "created", "")
    let operations = json_array(saved, "operations").map(operation_from)
    let validation = parse_document(
      @core.transaction_undo_plan_json(saved.stringify()),
      "撤销计划",
    )
    match json_field(validation, "error") {
      String(message) => fail(message)
      _ => ()
    }
    for operation in operations {
      match current_location(operation) {
        Some(relative) =>
          verify_fingerprint(
            safe_native_path(root, relative, internal=true),
            operation.fingerprint,
          )
        None => fail("操作记录阶段无效")
      }
    }
    for operation in operations {
      if operation.phase == "done" {
        operation.phase = "undo-staging"
        save_journal(
          root,
          id,
          journal_json(id, created, "undoing", operations, None),
        )
        move_exclusive(
          root,
          operation.target,
          operation.stage,
          operation.fingerprint,
        )
        operation.phase = "undo-staged"
      }
    }
    for operation in operations {
      if ["staged", "applying", "undo-staged", "restoring"].contains(
          operation.phase,
        ) {
        guard !@fs.exists(native_path(root, operation.source)) else {
          fail("原位置已被占用：" + operation.source)
        }
        operation.phase = "restoring"
        save_journal(
          root,
          id,
          journal_json(id, created, "undoing", operations, None),
        )
        move_exclusive(
          root,
          operation.stage,
          operation.source,
          operation.fingerprint,
        )
        operation.phase = "restored"
      }
    }
    let journal = journal_json(id, created, "undone", operations, None)
    save_journal(root, id, journal)
    release_lock(lock_path)
    lock_path = ""
    journal.stringify()
  } catch {
    error => {
      if lock_path != "" {
        release_lock(lock_path) catch {
          _ => ()
        }
      }
      json_error(error.to_string())
    }
  }
}
