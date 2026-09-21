///|
/// Native execution record for one manifest step. The record is persisted
/// before the step starts so an interrupted run remains inspectable.
priv struct NativeMigrationAction {
  id : String
  kind : String
  source : String
  target : String
  path : String
  content : String
  find : String
  replacement : String
  expected_sha256 : String
  backup : String
  created_directories : Array[String]
  mut phase : String
  skipped : Bool
  had_original : Bool
}

///|
let migration_state_directory = ".moonmigrate"

///|
fn migration_state_path(root : String) -> String {
  native_path(root, migration_state_directory)
}

///|
async fn ensure_migration_state(root : String) -> String {
  let state = migration_state_path(root)
  for name in ["history", "backups", "quarantine"] {
    let directory = native_path(state, name)
    if !@fs.exists(directory) {
      @fs.mkdir(directory, recursive=true)
    }
  }
  state
}

///|
async fn acquire_migration_lock(root : String) -> String {
  let state = ensure_migration_state(root)
  let lock = native_path(state, "lock")
  try {
    @fs.write_file(
      lock,
      ({ "created": @env.now().to_string() } : Json).stringify(),
      create_mode=CreateNew,
      sync=Full,
    )
    lock
  } catch {
    _ =>
      fail(
        "已有迁移正在执行；确认没有进程运行后再处理 .moonmigrate/lock",
      )
  }
}

///|
async fn release_migration_lock(path : String) -> Unit {
  if path != "" && @fs.exists(path) {
    @fs.remove(path)
  }
}

///|
async fn read_migration_state(root : String) -> Json {
  let path = native_path(migration_state_path(root), "state.json")
  if !@fs.exists(path) {
    return { "project": "", "version": 0 }
  }
  parse_document(read_text(path), "迁移状态")
}

///|
async fn save_migration_state(
  root : String,
  project : String,
  version : Int,
) -> Unit {
  ignore(ensure_migration_state(root))
  atomic_text(
    native_path(migration_state_path(root), "state.json"),
    (
      {
        "project": project,
        "version": version,
        "updated": @env.now().to_string(),
      } : Json).stringify(indent=2),
  )
}

///|
fn migration_action_json(action : NativeMigrationAction) -> Json {
  {
    "id": action.id,
    "op": action.kind,
    "from": action.source,
    "to": action.target,
    "path": action.path,
    "content": action.content,
    "find": action.find,
    "replace": action.replacement,
    "expectedSha256": action.expected_sha256,
    "backup": action.backup,
    "createdDirectories": action.created_directories.to_json(),
    "phase": action.phase,
    "skipped": action.skipped,
    "hadOriginal": action.had_original,
  }
}

///|
/// Persistent journals deliberately omit manifest text payloads. They are not
/// needed for rollback and may contain application configuration secrets.
fn migration_action_record_json(action : NativeMigrationAction) -> Json {
  {
    "id": action.id,
    "op": action.kind,
    "from": action.source,
    "to": action.target,
    "path": action.path,
    "expectedSha256": action.expected_sha256,
    "backup": action.backup,
    "createdDirectories": action.created_directories.to_json(),
    "phase": action.phase,
    "skipped": action.skipped,
    "hadOriginal": action.had_original,
  }
}

///|
fn migration_action_from(value : Json) -> NativeMigrationAction {
  {
    id: json_text(value, "id", ""),
    kind: json_text(value, "op", ""),
    source: json_text(value, "from", ""),
    target: json_text(value, "to", ""),
    path: json_text(value, "path", ""),
    content: json_text(value, "content", ""),
    find: json_text(value, "find", ""),
    replacement: json_text(value, "replace", ""),
    expected_sha256: json_text(value, "expectedSha256", ""),
    backup: json_text(value, "backup", ""),
    created_directories: json_strings(value, "createdDirectories"),
    phase: json_text(value, "phase", "pending"),
    skipped: json_bool(value, "skipped", false),
    had_original: json_bool(value, "hadOriginal", false),
  }
}

///|
fn migration_journal(
  id : String,
  project : String,
  from_version : Int,
  to_version : Int,
  status : String,
  actions : Array[NativeMigrationAction],
) -> Json {
  {
    "id": id,
    "project": project,
    "fromVersion": from_version,
    "toVersion": to_version,
    "status": status,
    "updated": @env.now().to_string(),
    "actions": actions.map(migration_action_record_json).to_json(),
  }
}

///|
async fn save_migration_journal(
  root : String,
  id : String,
  document : Json,
) -> Unit {
  ignore(ensure_migration_state(root))
  atomic_text(
    native_path(
      native_path(migration_state_path(root), "history"),
      id + ".json",
    ),
    document.stringify(indent=2),
  )
}

///|
fn step_optional(value : Json) -> Bool {
  json_bool(value, "optional", false)
}

///|
async fn regular_file_or_fail(path : String, label : String) -> Unit {
  guard @fs.kind(path, follow_symlink=false) is Regular else {
    fail(label + "必须是普通文件且不能是符号链接")
  }
}

///|
async fn verify_migration_hash(path : String, expected : String) -> Unit {
  if expected == "" {
    return
  }
  let actual = sha256(@fs.read_file(path).binary())
  guard actual == expected else {
    fail("文件摘要与 expectedSha256 不一致：" + path)
  }
}

///|
fn migration_backup_relative(id : String, index : Int) -> String {
  ".moonmigrate/backups/" + id + "/" + index.to_string()
}

///|
fn migration_quarantine_relative(
  id : String,
  index : Int,
  source : String,
) -> String {
  ".moonmigrate/quarantine/" +
  id +
  "/" +
  index.to_string() +
  "-" +
  base_name(source)
}

///|
/// Record every missing user directory that execution may create. Rollback
/// removes them deepest-first after reversing the file operation.
async fn missing_directories(
  root : String,
  destination : String,
  include_leaf : Bool,
) -> Array[String] {
  let directory = if include_leaf {
    destination
  } else {
    parent_name(destination)
  }
  if directory == "" {
    return []
  }
  let missing = []
  let mut relative = ""
  for part in directory.replace_all(old="\\", new="/").split("/") {
    relative = if relative == "" {
      part.to_owned()
    } else {
      relative + "/" + part.to_owned()
    }
    let full = safe_native_path(root, relative)
    if !@fs.exists(full) {
      missing.push(relative)
    }
  }
  missing
}

///|
/// Validate the real filesystem and precompute reversible action metadata.
async fn prepare_migration_actions(
  root : String,
  id : String,
  steps : Array[Json],
) -> Array[NativeMigrationAction] {
  let actions = []
  let targets : Map[String, Bool] = Map([])
  for index, step in steps {
    let kind = json_text(step, "op", "")
    let source = json_text(step, "from", "")
    let declared_target = json_text(step, "to", "")
    let path = json_text(step, "path", "")
    let optional = step_optional(step)
    let expected = json_text(step, "expectedSha256", "")
    let mut skipped = false
    let mut had_original = false
    let mut backup = ""
    let mut created_directories : Array[String] = []
    let mut target = declared_target
    match kind {
      "mkdir" => {
        let full = safe_native_path(root, path)
        if @fs.exists(full) {
          guard @fs.kind(full, follow_symlink=false) is Directory else {
            fail("建目录目标已被文件占用：" + path)
          }
          skipped = true
          had_original = true
        }
      }
      "move" | "copy" => {
        let from = safe_native_path(root, source)
        if !@fs.exists(from) {
          if optional {
            skipped = true
          } else {
            fail("源文件不存在：" + source)
          }
        } else {
          regular_file_or_fail(from, source)
          verify_migration_hash(from, expected)
        }
        let to = safe_native_path(root, target)
        guard !@fs.exists(to) else { fail("目标已存在：" + target) }
      }
      "write" => {
        let full = safe_native_path(root, path)
        if @fs.exists(full) {
          regular_file_or_fail(full, path)
          verify_migration_hash(full, expected)
          had_original = true
          backup = migration_backup_relative(id, index)
        } else if expected != "" {
          fail("expectedSha256 要求文件必须存在：" + path)
        }
      }
      "replace" => {
        let full = safe_native_path(root, path)
        if !@fs.exists(full) {
          if optional {
            skipped = true
          } else {
            fail("替换目标不存在：" + path)
          }
        } else {
          regular_file_or_fail(full, path)
          verify_migration_hash(full, expected)
          let old = read_text(full)
          guard old.contains(json_text(step, "find", "")) else {
            if optional {
              skipped = true
            } else {
              fail("替换目标没有找到指定文本：" + path)
            }
          }
          if !skipped {
            had_original = true
            backup = migration_backup_relative(id, index)
          }
        }
      }
      "quarantine" => {
        let from = safe_native_path(root, source)
        if !@fs.exists(from) {
          if optional {
            skipped = true
          } else {
            fail("隔离源文件不存在：" + source)
          }
        } else {
          regular_file_or_fail(from, source)
          verify_migration_hash(from, expected)
          target = migration_quarantine_relative(id, index, source)
        }
      }
      _ => fail("不支持的迁移操作：" + kind)
    }
    let claimed = match kind {
      "move" | "copy" | "quarantine" => target
      "mkdir" | "write" | "replace" => path
      _ => ""
    }
    if !skipped && targets.contains(claimed.to_lower()) {
      fail("多个步骤写入同一路径：" + claimed)
    }
    if !skipped {
      targets[claimed.to_lower()] = true
      created_directories = match kind {
        "mkdir" => missing_directories(root, path, true)
        "move" | "copy" => missing_directories(root, target, false)
        "write" => missing_directories(root, path, false)
        _ => []
      }
    }
    actions.push({
      id: json_text(step, "id", ""),
      kind,
      source,
      target,
      path,
      content: json_text(step, "content", ""),
      find: json_text(step, "find", ""),
      replacement: json_text(step, "replace", ""),
      expected_sha256: expected,
      backup,
      created_directories,
      phase: if skipped {
        "skipped"
      } else {
        "pending"
      },
      skipped,
      had_original,
    })
  }
  actions
}

///|
async fn move_without_replace(
  root : String,
  source : String,
  target : String,
  internal_source? : Bool = false,
  internal_target? : Bool = false,
) -> Unit {
  let from = safe_native_path(root, source, internal=internal_source)
  let to = safe_native_path(root, target, internal=internal_target)
  guard @fs.exists(from) else { fail("源文件不存在：" + source) }
  guard !@fs.exists(to) else { fail("目标已存在：" + target) }
  ensure_parent(to)
  @fs.rename(from, to, replace=false)
}

///|
async fn execute_migration_action(
  root : String,
  action : NativeMigrationAction,
) -> Unit {
  if action.skipped {
    return
  }
  match action.kind {
    "mkdir" => @fs.mkdir(safe_native_path(root, action.path), recursive=true)
    "move" => move_without_replace(root, action.source, action.target)
    "copy" => {
      let source = safe_native_path(root, action.source)
      let target = safe_native_path(root, action.target)
      ensure_parent(target)
      @fs.write_file(
        target,
        @fs.read_file(source),
        create_mode=CreateNew,
        sync=Full,
      )
    }
    "write" => {
      let target = safe_native_path(root, action.path)
      if action.had_original {
        move_without_replace(
          root,
          action.path,
          action.backup,
          internal_target=true,
        )
      }
      ensure_parent(target)
      @fs.write_file(target, action.content, create_mode=CreateNew, sync=Full)
    }
    "replace" => {
      let target = safe_native_path(root, action.path)
      let updated = read_text(target).replace_all(
        old=action.find,
        new=action.replacement,
      )
      move_without_replace(
        root,
        action.path,
        action.backup,
        internal_target=true,
      )
      @fs.write_file(target, updated, create_mode=CreateNew, sync=Full)
    }
    "quarantine" =>
      move_without_replace(
        root,
        action.source,
        action.target,
        internal_target=true,
      )
    _ => fail("不支持的迁移操作：" + action.kind)
  }
}

///|
async fn migration_core_plan(
  root : String,
  manifest_source : String,
  requested_target : Int?,
) -> (Json, Json) {
  let manifest = parse_document(manifest_source, "迁移清单")
  let state = read_migration_state(root)
  let current = match json_field(state, "version") {
    Number(value, ..) => value.to_int()
    _ => 0
  }
  let request : Json = {
    "manifest": manifest,
    "currentVersion": current,
    "targetVersion": match requested_target {
      Some(value) => value.to_json()
      None => Json::null()
    },
  }
  let plan = parse_document(
    @core.migration_plan_json(request.stringify()),
    "迁移计划",
  )
  match json_field(plan, "error") {
    String(message) => fail(message)
    _ => ()
  }
  let existing_project = json_text(state, "project", "")
  let project = json_text(plan, "project", "")
  guard existing_project == "" || existing_project == project else {
    fail("该目录属于另一个迁移项目：" + existing_project)
  }
  (plan, state)
}

///|
async fn unfinished_migration(root : String) -> String? {
  let history = native_path(migration_state_path(root), "history")
  if !@fs.exists(history) {
    return None
  }
  for name in @fs.readdir(history, include_hidden=false, sort=true) {
    if !name.has_suffix(".json") {
      continue
    }
    let record = parse_document(
      read_text(native_path(history, name)),
      "迁移记录",
    )
    if ["running", "failed"].contains(json_text(record, "status", "")) {
      return Some(json_text(record, "id", name))
    }
  }
  None
}

///|
pub async fn migration_preview_json(
  root_input : String,
  manifest_source : String,
  requested_target : Int?,
) -> String {
  try {
    let root = resolve_root(root_input)
    let (plan, _) = migration_core_plan(root, manifest_source, requested_target)
    let preview_id = "00000000-0000-0000-0000-000000000000"
    let actions = prepare_migration_actions(
      root,
      preview_id,
      json_array(plan, "steps"),
    )
    (
      {
        "plan": plan,
        "actions": actions.map(migration_action_json).to_json(),
        "ready": true,
      } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}

///|
pub async fn migration_apply_json(
  root_input : String,
  manifest_source : String,
  requested_target : Int?,
) -> String {
  let mut lock = ""
  try {
    let root = resolve_root(root_input)
    lock = acquire_migration_lock(root)
    if unfinished_migration(root) is Some(blocking_id) {
      fail("存在未完成迁移，请先回滚批次：" + blocking_id)
    }
    let (plan, _) = migration_core_plan(root, manifest_source, requested_target)
    let project = json_text(plan, "project", "")
    let from_version = match json_field(plan, "currentVersion") {
      Number(value, ..) => value.to_int()
      _ => 0
    }
    let to_version = match json_field(plan, "targetVersion") {
      Number(value, ..) => value.to_int()
      _ => from_version
    }
    if from_version == to_version {
      release_migration_lock(lock)
      lock = ""
      return ({ "status": "up-to-date", "version": to_version } : Json).stringify()
    }
    let id = operation_id()
    let actions = prepare_migration_actions(root, id, json_array(plan, "steps"))
    save_migration_journal(
      root,
      id,
      migration_journal(
        id, project, from_version, to_version, "running", actions,
      ),
    )
    for action in actions {
      if action.skipped {
        continue
      }
      action.phase = "running"
      save_migration_journal(
        root,
        id,
        migration_journal(
          id, project, from_version, to_version, "running", actions,
        ),
      )
      execute_migration_action(root, action)
      action.phase = "done"
      save_migration_journal(
        root,
        id,
        migration_journal(
          id, project, from_version, to_version, "running", actions,
        ),
      )
    }
    save_migration_state(root, project, to_version)
    let result = migration_journal(
      id, project, from_version, to_version, "completed", actions,
    )
    save_migration_journal(root, id, result)
    release_migration_lock(lock)
    lock = ""
    result.stringify()
  } catch {
    error => {
      release_migration_lock(lock) catch {
        _ => ()
      }
      json_error(error.to_string())
    }
  }
}

///|
async fn rollback_migration_action(
  root : String,
  action : NativeMigrationAction,
) -> Unit {
  if action.skipped || action.phase == "pending" {
    return
  }
  match action.kind {
    "mkdir" => ()
    "move" => {
      let target = safe_native_path(root, action.target)
      if @fs.exists(target) {
        move_without_replace(root, action.target, action.source)
      }
    }
    "copy" => {
      let target = safe_native_path(root, action.target)
      if @fs.exists(target) {
        @fs.remove(target)
      }
    }
    "write" | "replace" => {
      let target = safe_native_path(root, action.path)
      if action.had_original {
        let backup = safe_native_path(root, action.backup, internal=true)
        if @fs.exists(backup) {
          if @fs.exists(target) {
            @fs.remove(target)
          }
          move_without_replace(
            root,
            action.backup,
            action.path,
            internal_source=true,
          )
        }
      } else if @fs.exists(target) {
        @fs.remove(target)
      }
    }
    "quarantine" => {
      let quarantined = safe_native_path(root, action.target, internal=true)
      if @fs.exists(quarantined) {
        move_without_replace(
          root,
          action.target,
          action.source,
          internal_source=true,
        )
      }
    }
    _ => fail("无法回滚未知操作：" + action.kind)
  }
  for reverse_index = 0
      reverse_index < action.created_directories.length()
      reverse_index = reverse_index + 1 {
    let index = action.created_directories.length() - reverse_index - 1
    let directory = safe_native_path(root, action.created_directories[index])
    if @fs.exists(directory) {
      @fs.rmdir(directory, recursive=false) catch {
        _ => ()
      }
    }
  }
}

///|
pub async fn migration_rollback_json(
  root_input : String,
  id : String,
) -> String {
  let mut lock = ""
  try {
    guard valid_operation_id(id) else { fail("迁移批次编号不合法") }
    let root = resolve_root(root_input)
    lock = acquire_migration_lock(root)
    let path = native_path(
      native_path(migration_state_path(root), "history"),
      id + ".json",
    )
    guard @fs.exists(path) else { fail("没有找到迁移记录") }
    let saved = parse_document(read_text(path), "迁移记录")
    let status = json_text(saved, "status", "")
    guard status != "rolled-back" else {
      release_migration_lock(lock)
      return saved.stringify()
    }
    guard ["completed", "running", "failed"].contains(status) else {
      fail("当前迁移状态不能回滚：" + status)
    }
    let state = read_migration_state(root)
    let installed_version = match json_field(state, "version") {
      Number(value, ..) => value.to_int()
      _ => 0
    }
    let saved_from_version = match json_field(saved, "fromVersion") {
      Number(value, ..) => value.to_int()
      _ => 0
    }
    let saved_to_version = match json_field(saved, "toVersion") {
      Number(value, ..) => value.to_int()
      _ => saved_from_version
    }
    let expected_version = if status == "completed" {
      saved_to_version
    } else {
      saved_from_version
    }
    guard installed_version == expected_version else {
      fail(
        "不能跨过其他迁移回滚；当前版本为 " +
        installed_version.to_string(),
      )
    }
    let actions = json_array(saved, "actions").map(migration_action_from)
    for reverse_index = 0
        reverse_index < actions.length()
        reverse_index = reverse_index + 1 {
      let index = actions.length() - reverse_index - 1
      rollback_migration_action(root, actions[index])
      actions[index].phase = "rolled-back"
    }
    let project = json_text(saved, "project", "")
    let from_version = saved_from_version
    let to_version = saved_to_version
    save_migration_state(root, project, from_version)
    let result = migration_journal(
      id, project, from_version, to_version, "rolled-back", actions,
    )
    save_migration_journal(root, id, result)
    release_migration_lock(lock)
    lock = ""
    result.stringify()
  } catch {
    error => {
      release_migration_lock(lock) catch {
        _ => ()
      }
      json_error(error.to_string())
    }
  }
}

///|
pub async fn migration_status_json(root_input : String) -> String {
  try {
    let root = resolve_root(root_input)
    let state = read_migration_state(root)
    let history_path = native_path(migration_state_path(root), "history")
    let records : Array[Json] = []
    if @fs.exists(history_path) {
      for name in @fs.readdir(history_path, include_hidden=false, sort=true) {
        if name.has_suffix(".json") {
          records.push(
            parse_document(
              read_text(native_path(history_path, name)),
              "迁移记录",
            ),
          )
        }
      }
    }
    ({ "state": state, "history": records.to_json() } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}
