///|
/// One portable filesystem operation in a versioned migration. Empty fields
/// are ignored unless the operation kind requires them.
pub(all) struct MigrationStep {
  id : String
  kind : String
  source : String
  target : String
  path : String
  content : String
  find : String
  replacement : String
  expected_sha256 : String
  optional : Bool
} derive(Eq, Debug)

///|
/// A migration advances exactly one application-data version range.
pub(all) struct Migration {
  id : String
  from_version : Int
  to_version : Int
  description : String
  steps : Array[MigrationStep]
} derive(Eq, Debug)

///|
/// A manifest owns an ordered, contiguous history for one application.
pub(all) struct MigrationManifest {
  format_version : Int
  project : String
  migrations : Array[Migration]
} derive(Eq, Debug)

///|
pub(all) struct MigrationPlan {
  project : String
  current_version : Int
  target_version : Int
  migrations : Array[Migration]
  steps : Array[MigrationStep]
} derive(Eq, Debug)

///|
fn migration_bool_field(value : Json, key : String, fallback : Bool) -> Bool {
  match field(value, key) {
    true => true
    false => false
    _ => fallback
  }
}

///|
fn decode_migration_step(value : Json) -> MigrationStep {
  {
    id: text_field(value, "id", ""),
    kind: text_field(value, "op", "").to_lower(),
    source: text_field(value, "from", ""),
    target: text_field(value, "to", ""),
    path: text_field(value, "path", ""),
    content: text_field(value, "content", ""),
    find: text_field(value, "find", ""),
    replacement: text_field(value, "replace", ""),
    expected_sha256: text_field(value, "expectedSha256", "").to_lower(),
    optional: migration_bool_field(value, "optional", false),
  }
}

///|
fn decode_migration(value : Json) -> Migration {
  {
    id: text_field(value, "id", ""),
    from_version: integer_field(value, "fromVersion", -1),
    to_version: integer_field(value, "toVersion", -1),
    description: text_field(value, "description", ""),
    steps: array_field(value, "steps").map(decode_migration_step),
  }
}

///|
pub fn decode_migration_manifest(value : Json) -> MigrationManifest {
  {
    format_version: integer_field(value, "formatVersion", 1),
    project: text_field(value, "project", ""),
    migrations: array_field(value, "migrations").map(decode_migration),
  }
}

///|
fn identifier_error(value : String) -> String? {
  if value == "" || value.length() > 80 {
    return Some("标识不能为空且不能超过 80 个字符")
  }
  if !value.all(character => {
      (character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      character.is_ascii_digit() ||
      ['-', '_', '.'].contains(character)
    }) {
    return Some("标识只能包含字母、数字、点、横线和下划线")
  }
  None
}

///|
fn sha256_text_valid(value : String) -> Bool {
  value.length() == 64 &&
  value.all(character => {
    character.is_ascii_digit() || (character >= 'a' && character <= 'f')
  })
}

///|
fn migration_step_paths(step : MigrationStep) -> Array[String] {
  match step.kind {
    "move" | "copy" => [step.source, step.target]
    "mkdir" | "write" | "replace" => [step.path]
    "quarantine" => [step.source]
    _ => []
  }
}

///|
pub fn validate_migration_step(step : MigrationStep) -> Array[String] {
  let errors = []
  if identifier_error(step.id) is Some(message) {
    errors.push("步骤 " + step.id + "：" + message)
  }
  let supported = ["mkdir", "move", "copy", "write", "replace", "quarantine"]
  if !supported.contains(step.kind) {
    errors.push("步骤 " + step.id + " 使用未知操作：" + step.kind)
    return errors
  }
  for path in migration_step_paths(step) {
    if path_error(path) is Some(message) {
      errors.push("步骤 " + step.id + " 的路径不安全：" + message)
    }
  }
  if ["move", "copy"].contains(step.kind) && step.source == step.target {
    errors.push(
      "步骤 " + step.id + " 的源路径和目标路径不能相同",
    )
  }
  if step.kind == "replace" && step.find == "" {
    errors.push("步骤 " + step.id + " 的查找文本不能为空")
  }
  if step.expected_sha256 != "" && !sha256_text_valid(step.expected_sha256) {
    errors.push(
      "步骤 " +
      step.id +
      " 的 expectedSha256 不是 64 位十六进制摘要",
    )
  }
  errors
}

///|
/// Validate the whole history, including version continuity and identifiers.
pub fn validate_migration_manifest(
  manifest : MigrationManifest,
) -> Array[String] {
  let errors = []
  if manifest.format_version != 1 {
    errors.push("只支持 formatVersion 1")
  }
  if identifier_error(manifest.project) is Some(message) {
    errors.push("project：" + message)
  }
  if manifest.migrations.length() == 0 {
    errors.push("至少需要一条迁移")
    return errors
  }
  let migration_ids : Map[String, Bool] = Map([])
  let from_versions : Map[Int, Bool] = Map([])
  for migration in manifest.migrations {
    if identifier_error(migration.id) is Some(message) {
      errors.push("迁移 " + migration.id + "：" + message)
    }
    if migration_ids.contains(migration.id) {
      errors.push("迁移 ID 重复：" + migration.id)
    }
    migration_ids[migration.id] = true
    if migration.from_version < 0 ||
      migration.to_version <= migration.from_version {
      errors.push("迁移 " + migration.id + " 的版本范围无效")
    }
    if from_versions.contains(migration.from_version) {
      errors.push(
        "版本 " +
        migration.from_version.to_string() +
        " 存在多条迁移分支",
      )
    }
    from_versions[migration.from_version] = true
    if migration.steps.length() == 0 {
      errors.push("迁移 " + migration.id + " 没有步骤")
    }
    let step_ids : Map[String, Bool] = Map([])
    for step in migration.steps {
      if step_ids.contains(step.id) {
        errors.push(
          "迁移 " + migration.id + " 的步骤 ID 重复：" + step.id,
        )
      }
      step_ids[step.id] = true
      errors.push_iter(validate_migration_step(step).iter())
    }
  }
  errors
}

///|
fn sorted_migrations(values : Array[Migration]) -> Array[Migration] {
  let result = values.copy()
  result.sort_by((left, right) => {
    if left.from_version == right.from_version {
      left.to_version - right.to_version
    } else {
      left.from_version - right.from_version
    }
  })
  result
}

///|
/// Resolve a unique, contiguous path from the installed version to the target.
pub fn build_migration_plan(
  manifest : MigrationManifest,
  current_version : Int,
  requested_target : Int?,
) -> (MigrationPlan?, Array[String]) {
  let errors = validate_migration_manifest(manifest)
  if errors.length() > 0 {
    return (None, errors)
  }
  if current_version < 0 {
    return (None, ["currentVersion 不能小于 0"])
  }
  let ordered = sorted_migrations(manifest.migrations)
  let latest = ordered.fold(init=0, (highest, migration) => {
    if migration.to_version > highest {
      migration.to_version
    } else {
      highest
    }
  })
  let target = requested_target.unwrap_or(latest)
  if target < current_version {
    return (None, ["目标版本低于当前版本，请使用回滚命令"])
  }
  if target > latest {
    return (None, ["目标版本超过清单的最新版本"])
  }
  let selected = []
  let steps = []
  let mut cursor = current_version
  while cursor < target {
    let mut next : Migration? = None
    for migration in ordered {
      if migration.from_version == cursor {
        next = Some(migration)
        break
      }
    }
    match next {
      None =>
        return (
          None,
          ["迁移链在版本 " + cursor.to_string() + " 处中断"],
        )
      Some(migration) => {
        if migration.to_version > target {
          return (None, ["目标版本不是迁移边界"])
        }
        selected.push(migration)
        steps.push_iter(migration.steps.iter())
        cursor = migration.to_version
      }
    }
  }
  (
    Some({
      project: manifest.project,
      current_version,
      target_version: target,
      migrations: selected,
      steps,
    }),
    [],
  )
}

///|
fn migration_step_json(step : MigrationStep) -> Json {
  {
    "id": step.id,
    "op": step.kind,
    "from": step.source,
    "to": step.target,
    "path": step.path,
    "content": step.content,
    "find": step.find,
    "replace": step.replacement,
    "expectedSha256": step.expected_sha256,
    "optional": step.optional,
  }
}

///|
fn migration_json(migration : Migration) -> Json {
  {
    "id": migration.id,
    "fromVersion": migration.from_version,
    "toVersion": migration.to_version,
    "description": migration.description,
    "steps": migration.steps.map(migration_step_json).to_json(),
  }
}

///|
fn migration_plan_json_value(plan : MigrationPlan) -> Json {
  {
    "project": plan.project,
    "currentVersion": plan.current_version,
    "targetVersion": plan.target_version,
    "migrationCount": plan.migrations.length(),
    "stepCount": plan.steps.length(),
    "migrations": plan.migrations.map(migration_json).to_json(),
    "steps": plan.steps.map(migration_step_json).to_json(),
  }
}

///|
/// Stable JSON boundary for native, browser, and third-party adapters.
pub fn migration_plan_json(input : String) -> String {
  let document = @json.parse(input) catch {
    _ =>
      return ({ "error": "迁移输入不是合法 JSON" } : Json).stringify()
  }
  let manifest = decode_migration_manifest(field(document, "manifest"))
  let current_version = integer_field(document, "currentVersion", 0)
  let requested = match field(document, "targetVersion") {
    Number(value, ..) => Some(value.to_int())
    String(value) => Some(@string.parse_int(value)) catch { _ => None }
    _ => None
  }
  let (plan, errors) = build_migration_plan(
    manifest, current_version, requested,
  )
  match plan {
    Some(value) => migration_plan_json_value(value).stringify()
    None =>
      ({ "error": errors.join("；"), "errors": errors } : Json).stringify()
  }
}
