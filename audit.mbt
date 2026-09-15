///|
/// Summary used by the UI, CLI and exported diagnostics.
pub(all) struct PlanSummary {
  ready : Int
  conflict : Int
  invalid : Int
  unchanged : Int
  excluded : Int
  total : Int
  duplicate_groups : Int
  duplicate_bytes : String
} derive(Eq, Debug)

///|
/// Decode the filesystem adapter's inventory without trusting object shape.
fn decode_files(value : Json) -> Array[FileEntry] {
  array_field(value, "files").map(file => {
    path: text_field(file, "path", ""),
    name: text_field(file, "name", ""),
    month: text_field(file, "month", ""),
    size: text_field(file, "size", "0"),
    hash: text_field(file, "hash", ""),
  })
}

///|
/// Decode nested arrays of relative paths.
fn decode_groups(value : Json, key : String) -> Array[Array[String]] {
  array_field(value, key).map(group => {
    match group {
      Array(items) =>
        items.map(item => {
          match item {
            String(text) => text
            _ => ""
          }
        })
      _ => []
    }
  })
}

///|
/// Verify that every selection was produced by this exact inventory. This is
/// deliberately repeated inside MoonBit even though the UI only offers known
/// checkboxes: CLI and HTTP callers are untrusted.
pub fn validate_selections(
  files : Array[FileEntry],
  duplicate_groups : Array[Array[String]],
  options : Options,
) -> Array[String] {
  let errors = []
  let known : Map[String, Bool] = Map([])
  for file in files {
    known[file.path] = true
  }
  for selected in options.excluded {
    if !known.contains(selected) {
      errors.push("文件不在本次扫描中：" + selected)
    }
  }
  let duplicates : Map[String, Bool] = Map([])
  for group in duplicate_groups {
    for item in group {
      duplicates[item] = true
    }
  }
  for selected in options.quarantine {
    if !known.contains(selected) {
      errors.push("文件不在本次扫描中：" + selected)
    } else if !duplicates.contains(selected) {
      errors.push("未经内容比对确认的重复文件：" + selected)
    }
    if options.excluded.contains(selected) {
      errors.push("文件不能同时被排除和隔离：" + selected)
    }
  }
  for group in duplicate_groups {
    if group.length() > 0 &&
      group.all(item => options.quarantine.contains(item)) {
      errors.push("每组重复文件必须保留至少一份")
    }
  }
  errors
}

///|
/// Detect a target whose parent segment is an existing file or link. The
/// planner checks complete target collisions; this audit covers intermediate
/// path components using facts collected by the OS adapter.
pub fn audit_parent_paths(
  rows : Array[PlanRow],
  occupied_paths : Array[String],
  directories : Array[String],
) -> Array[PlanRow] {
  let occupied : Map[String, Bool] = Map([])
  let folders : Map[String, Bool] = Map([])
  for item in occupied_paths {
    occupied[item.to_lower()] = true
  }
  for item in directories {
    folders[item.to_lower()] = true
  }
  rows.map(row => {
    if row.status != "ready" {
      return row
    }
    let mut parent = parent_path(row.target)
    while parent != "" {
      let key = parent.to_lower()
      if occupied.contains(key) && !folders.contains(key) {
        return {
          ..row,
          status: "conflict",
          reason: "目标父路径被文件或链接占用",
        }
      }
      parent = parent_path(parent)
    }
    row
  })
}

///|
/// Potential duplicate bytes are all members after one keeper per confirmed
/// group. Decimal strings keep totals exact for large archives.
pub fn duplicate_reclaimable_bytes(
  files : Array[FileEntry],
  duplicate_groups : Array[Array[String]],
) -> String {
  let sizes : Map[String, String] = Map([])
  for file in files {
    sizes[file.path] = normalize_decimal(file.size).unwrap_or("0")
  }
  let mut total = "0"
  for group in duplicate_groups {
    for index = 1; index < group.length(); index = index + 1 {
      total = decimal_add(total, sizes.get(group[index]).unwrap_or("0"))
    }
  }
  total
}

///|
/// Count every plan state and attach duplicate statistics.
pub fn summarize_plan(
  rows : Array[PlanRow],
  files : Array[FileEntry],
  duplicate_groups : Array[Array[String]],
) -> PlanSummary {
  let mut ready = 0
  let mut conflict = 0
  let mut invalid = 0
  let mut unchanged = 0
  let mut excluded = 0
  for row in rows {
    match row.status {
      "ready" => ready = ready + 1
      "conflict" => conflict = conflict + 1
      "invalid" => invalid = invalid + 1
      "unchanged" => unchanged = unchanged + 1
      "excluded" => excluded = excluded + 1
      _ => invalid = invalid + 1
    }
  }
  {
    ready,
    conflict,
    invalid,
    unchanged,
    excluded,
    total: rows.length(),
    duplicate_groups: duplicate_groups.length(),
    duplicate_bytes: duplicate_reclaimable_bytes(files, duplicate_groups),
  }
}

///|
/// Serialize summary keys using the camelCase contract consumed by the web UI.
fn summary_json(summary : PlanSummary) -> Json {
  {
    "ready": summary.ready,
    "conflict": summary.conflict,
    "invalid": summary.invalid,
    "unchanged": summary.unchanged,
    "excluded": summary.excluded,
    "total": summary.total,
    "duplicateGroups": summary.duplicate_groups,
    "duplicateBytes": summary.duplicate_bytes,
  }
}

///|
/// MoonBit-first planning boundary. It owns selection validation, deterministic
/// planning, parent-path auditing and summary calculation in one pure call.
pub fn plan_bundle_json(input : String) -> String {
  let document = @json.parse(input) catch {
    _ => return ({ "error": "输入不是合法 JSON" } : Json).stringify()
  }
  let files = decode_files(document)
  let occupied = strings_field(document, "occupied")
  let directories = strings_field(document, "directories")
  let duplicates = decode_groups(document, "duplicates")
  let options = decode_options(field(document, "options"))
  let errors = validate_options(options)
  errors.push_iter(validate_selections(files, duplicates, options).iter())
  if errors.length() > 0 {
    return ({ "error": errors.join("；") } : Json).stringify()
  }
  let initial = plan(files, occupied, options)
  let rows = audit_parent_paths(initial, occupied, directories)
  let summary = summarize_plan(rows, files, duplicates)
  ({ "rows": rows.to_json(), "summary": summary_json(summary) } : Json).stringify()
}
