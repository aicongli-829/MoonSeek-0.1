///| Portable inventory record saved by the snapshot command. Modification time
/// is intentionally omitted: content digests make comparisons reproducible.
pub(all) struct SnapshotFile {
  path : String
  name : String
  month : String
  size : String
  hash : String
} derive(Eq, Debug, ToJson)

///| One difference between a saved inventory and a current scan.
pub(all) struct SnapshotChange {
  kind : String
  before_path : String
  after_path : String
  before_size : String
  after_size : String
  bytes_changed : String
  reason : String
} derive(Eq, Debug, ToJson)

///| Summary of a comparison. Byte totals remain decimal strings.
pub(all) struct SnapshotDiffSummary {
  added : Int
  removed : Int
  modified : Int
  moved : Int
  unchanged : Int
  bytes_added : String
  bytes_removed : String
  net_bytes : String
} derive(Eq, Debug)

///| Full deterministic comparison result.
pub(all) struct SnapshotDiff {
  summary : SnapshotDiffSummary
  changes : Array[SnapshotChange]
} derive(Eq, Debug)

///| Convert an adapter inventory entry into its persisted representation.
fn snapshot_file(file : FileEntry) -> SnapshotFile {
  {
    path: file.path,
    name: file.name,
    month: file.month,
    size: normalize_decimal(file.size).unwrap_or("0"),
    hash: file.hash.to_lower(),
  }
}

///| Decode a snapshot file list without trusting the serialized record shape.
fn decode_snapshot_files(value : Json, key : String) -> Array[SnapshotFile] {
  array_field(value, key).map(file => {
    path: text_field(file, "path", ""),
    name: text_field(file, "name", ""),
    month: text_field(file, "month", ""),
    size: text_field(file, "size", "0"),
    hash: text_field(file, "hash", "").to_lower(),
  })
}

///| Validate saved and current records before comparing them.
pub fn validate_snapshot_files(files : Array[SnapshotFile]) -> Array[String] {
  let errors = []
  let paths : Map[String, Bool] = Map([])
  for file in files {
    if path_error(file.path) is Some(_) {
      errors.push("快照包含不安全路径：" + file.path)
    }
    if file.name == "" || base_name(file.path) != file.name {
      errors.push("快照文件名与路径不一致：" + file.path)
    }
    if normalize_decimal(file.size) is None {
      errors.push("快照包含无效大小：" + file.path)
    }
    if file.hash == "" {
      errors.push("快照缺少内容摘要：" + file.path)
    }
    let key = file.path.to_lower()
    if paths.contains(key) {
      errors.push("快照包含重复路径：" + file.path)
    }
    paths[key] = true
  }
  errors
}

///| Stable content identity used only after exact-path comparisons are removed.
fn snapshot_content_key(file : SnapshotFile) -> String {
  normalize_decimal(file.size).unwrap_or("0") + ":" + file.hash.to_lower()
}

///| Change order keeps the most actionable differences first.
fn snapshot_kind_order(kind : String) -> Int {
  match kind {
    "modified" => 0
    "moved" => 1
    "added" => 2
    "removed" => 3
    _ => 4
  }
}

///| Sort changes independently of filesystem enumeration order.
pub fn sort_snapshot_changes(changes : Array[SnapshotChange]) -> Array[SnapshotChange] {
  let result = changes.copy()
  result.sort_by((left, right) => {
    let kind_order = snapshot_kind_order(left.kind) - snapshot_kind_order(right.kind)
    if kind_order != 0 {
      kind_order
    } else {
      let left_path = if left.after_path == "" { left.before_path } else { left.after_path }
      let right_path = if right.after_path == "" { right.before_path } else { right.after_path }
      natural_compare(left_path, right_path)
    }
  })
  result
}

///| Absolute difference between exact decimal sizes.
fn snapshot_size_difference(left : String, right : String) -> String {
  if decimal_compare(left, right) >= 0 {
    decimal_subtract(left, right).unwrap_or("0")
  } else {
    decimal_subtract(right, left).unwrap_or("0")
  }
}

///| Compare two inventories. Matching paths are resolved first. Remaining files
/// with the same size and digest are paired as rename/move candidates.
pub fn compare_snapshots(
  before : Array[SnapshotFile],
  after : Array[SnapshotFile],
) -> SnapshotDiff {
  let before_by_path : Map[String, Int] = Map([])
  let after_by_path : Map[String, Int] = Map([])
  for index, file in before { before_by_path[file.path.to_lower()] = index }
  for index, file in after { after_by_path[file.path.to_lower()] = index }
  let before_matched = Array::make(before.length(), false)
  let after_matched = Array::make(after.length(), false)
  let changes = []
  let mut unchanged = 0
  let mut modified = 0
  let mut moved = 0
  let mut added = 0
  let mut removed = 0
  let mut bytes_added = "0"
  let mut bytes_removed = "0"
  for before_index, old in before {
    match after_by_path.get(old.path.to_lower()) {
      None => ()
      Some(after_index) => {
        let current = after[after_index]
        before_matched[before_index] = true
        after_matched[after_index] = true
        if old.hash == current.hash && normalize_decimal(old.size) == normalize_decimal(current.size) {
          unchanged = unchanged + 1
        } else {
          modified = modified + 1
          let old_size = normalize_decimal(old.size).unwrap_or("0")
          let new_size = normalize_decimal(current.size).unwrap_or("0")
          if decimal_compare(new_size, old_size) >= 0 {
            bytes_added = decimal_add(bytes_added, decimal_subtract(new_size, old_size).unwrap_or("0"))
          } else {
            bytes_removed = decimal_add(bytes_removed, decimal_subtract(old_size, new_size).unwrap_or("0"))
          }
          changes.push({
            kind: "modified",
            before_path: old.path,
            after_path: current.path,
            before_size: old_size,
            after_size: new_size,
            bytes_changed: snapshot_size_difference(old_size, new_size),
            reason: "相同路径的内容摘要发生变化",
          })
        }
      }
    }
  }
  let old_content : Map[String, Array[Int]] = Map([])
  let new_content : Map[String, Array[Int]] = Map([])
  let content_order = []
  for index, file in before {
    if before_matched[index] { continue }
    let key = snapshot_content_key(file)
    if !old_content.contains(key) {
      old_content[key] = []
      content_order.push(key)
    }
    old_content[key].push(index)
  }
  for index, file in after {
    if after_matched[index] { continue }
    let key = snapshot_content_key(file)
    if !new_content.contains(key) { new_content[key] = [] }
    new_content[key].push(index)
  }
  for key in content_order {
    if !new_content.contains(key) { continue }
    let old_indices = old_content[key]
    let new_indices = new_content[key]
    old_indices.sort_by((left, right) => natural_compare(before[left].path, before[right].path))
    new_indices.sort_by((left, right) => natural_compare(after[left].path, after[right].path))
    let pairs = if old_indices.length() < new_indices.length() { old_indices.length() } else { new_indices.length() }
    for position = 0; position < pairs; position = position + 1 {
      let old_index = old_indices[position]
      let new_index = new_indices[position]
      let old = before[old_index]
      let current = after[new_index]
      before_matched[old_index] = true
      after_matched[new_index] = true
      moved = moved + 1
      changes.push({
        kind: "moved",
        before_path: old.path,
        after_path: current.path,
        before_size: normalize_decimal(old.size).unwrap_or("0"),
        after_size: normalize_decimal(current.size).unwrap_or("0"),
        bytes_changed: "0",
        reason: "相同大小和内容摘要出现在新路径",
      })
    }
  }
  for index, old in before {
    if before_matched[index] { continue }
    let size = normalize_decimal(old.size).unwrap_or("0")
    removed = removed + 1
    bytes_removed = decimal_add(bytes_removed, size)
    changes.push({
      kind: "removed",
      before_path: old.path,
      after_path: "",
      before_size: size,
      after_size: "0",
      bytes_changed: size,
      reason: "当前扫描中已不存在",
    })
  }
  for index, current in after {
    if after_matched[index] { continue }
    let size = normalize_decimal(current.size).unwrap_or("0")
    added = added + 1
    bytes_added = decimal_add(bytes_added, size)
    changes.push({
      kind: "added",
      before_path: "",
      after_path: current.path,
      before_size: "0",
      after_size: size,
      bytes_changed: size,
      reason: "保存快照后新增",
    })
  }
  let net_bytes = if decimal_compare(bytes_added, bytes_removed) >= 0 {
    "+" + decimal_subtract(bytes_added, bytes_removed).unwrap_or("0")
  } else {
    "-" + decimal_subtract(bytes_removed, bytes_added).unwrap_or("0")
  }
  {
    summary: {
      added,
      removed,
      modified,
      moved,
      unchanged,
      bytes_added,
      bytes_removed,
      net_bytes,
    },
    changes: sort_snapshot_changes(changes),
  }
}

///| Serialize summary keys for JavaScript consumers.
fn snapshot_summary_json(summary : SnapshotDiffSummary) -> Json {
  {
    "added": summary.added,
    "removed": summary.removed,
    "modified": summary.modified,
    "moved": summary.moved,
    "unchanged": summary.unchanged,
    "bytesAdded": summary.bytes_added,
    "bytesRemoved": summary.bytes_removed,
    "netBytes": summary.net_bytes,
  }
}

///| Save a normalized, naturally sorted snapshot document.
pub fn create_snapshot_json(input : String) -> String {
  let document = @json.parse(input) catch {
    _ => return ({ "error": "快照输入不是合法 JSON" } : Json).stringify()
  }
  let created = text_field(document, "created", "")
  let files = decode_files(document).map(snapshot_file)
  let errors = validate_snapshot_files(files)
  if errors.length() > 0 {
    return ({ "error": errors.join("；") } : Json).stringify()
  }
  files.sort_by((left, right) => natural_compare(left.path, right.path))
  ({ "schemaVersion": 1, "created": created, "files": files.to_json() } : Json).stringify()
}

///| Compare a saved snapshot document with current adapter records.
pub fn compare_snapshot_json(input : String) -> String {
  let document = @json.parse(input) catch {
    _ => return ({ "error": "快照对比输入不是合法 JSON" } : Json).stringify()
  }
  let snapshot = field(document, "snapshot")
  if integer_field(snapshot, "schemaVersion", 0) != 1 {
    return ({ "error": "不支持的快照版本" } : Json).stringify()
  }
  let before = decode_snapshot_files(snapshot, "files")
  let current_document = field(document, "current")
  let after = decode_files(current_document).map(snapshot_file)
  let errors = validate_snapshot_files(before)
  errors.push_iter(validate_snapshot_files(after).iter())
  if errors.length() > 0 {
    return ({ "error": errors.join("；") } : Json).stringify()
  }
  let result = compare_snapshots(before, after)
  ({ "summary": snapshot_summary_json(result.summary), "changes": result.changes.to_json() } : Json).stringify()
}
