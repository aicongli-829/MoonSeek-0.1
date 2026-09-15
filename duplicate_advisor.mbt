///|
/// Non-destructive advice for one byte-confirmed duplicate group.
pub(all) struct DuplicateAdvice {
  keeper : String
  quarantine : Array[String]
  size_each : String
  reclaimable_bytes : String
  reason : String
} derive(Eq, Debug, ToJson)

///|
/// Detect common copy suffixes in Chinese and English. The score is used only
/// to choose a suggested keeper and never causes automatic deletion.
pub fn duplicate_copy_marker_score(path : String) -> Int {
  let stem = split_extension(base_name(path)).0.to_lower()
  let mut score = 0
  for marker in ["副本", "复制", "copy", "backup", "备份"] {
    if stem.contains(marker) {
      score = score + 4
    }
  }
  if stem.has_suffix(" (1)") || stem.has_suffix("_1") || stem.has_suffix("-1") {
    score = score + 2
  }
  if stem.contains("copy of ") || stem.contains(" - copy") {
    score = score + 3
  }
  score
}

///|
/// Compare keeper candidates. Prefer a name without copy markers, then a
/// shallower and shorter path, then natural ordering for reproducibility.
pub fn duplicate_keeper_compare(left : FileEntry, right : FileEntry) -> Int {
  let marker = duplicate_copy_marker_score(left.path) -
    duplicate_copy_marker_score(right.path)
  if marker != 0 {
    marker
  } else {
    let depth = analysis_depth(left.path) - analysis_depth(right.path)
    if depth != 0 {
      depth
    } else {
      let length = left.path.length() - right.path.length()
      if length != 0 {
        length
      } else {
        natural_compare(left.path, right.path)
      }
    }
  }
}

///|
/// Explain the dominant factor behind the keeper selection.
fn duplicate_keeper_reason(
  keeper : FileEntry,
  group : Array[FileEntry],
) -> String {
  let best_marker = duplicate_copy_marker_score(keeper.path)
  if group.any(file => duplicate_copy_marker_score(file.path) > best_marker) {
    "优先保留文件名中没有“副本/备份/copy”标记的版本"
  } else {
    let keeper_depth = analysis_depth(keeper.path)
    if group.any(file => analysis_depth(file.path) > keeper_depth) {
      "优先保留目录层级较浅、较容易找到的版本"
    } else if group.any(file => file.path.length() > keeper.path.length()) {
      "优先保留路径较短的版本"
    } else {
      "路径条件相同，按自然文件名顺序选择"
    }
  }
}

///|
/// Produce advice for every confirmed group, preserving exact byte totals.
pub fn advise_duplicate_groups(
  files : Array[FileEntry],
  groups : Array[Array[String]],
) -> Array[DuplicateAdvice] {
  let by_path : Map[String, FileEntry] = Map([])
  for file in files {
    by_path[file.path] = file
  }
  let advice = []
  for paths in groups {
    let members = []
    for item in paths {
      match by_path.get(item) {
        Some(file) => members.push(file)
        None => ()
      }
    }
    if members.length() < 2 {
      continue
    }
    members.sort_by(duplicate_keeper_compare)
    let keeper = members[0]
    let quarantine = members[1:].map(file => file.path)
    let size = normalize_decimal(keeper.size).unwrap_or("0")
    advice.push({
      keeper: keeper.path,
      quarantine,
      size_each: size,
      reclaimable_bytes: decimal_multiply_small(size, quarantine.length()).unwrap_or(
        "0",
      ),
      reason: duplicate_keeper_reason(keeper, members),
    })
  }
  advice.sort_by((left, right) => natural_compare(left.keeper, right.keeper))
  advice
}

///|
/// Boundary for clients that only need duplicate suggestions.
pub fn duplicate_advice_json(input : String) -> String {
  let document = @json.parse(input) catch {
    _ =>
      return ({ "error": "重复建议输入不是合法 JSON" } : Json).stringify()
  }
  let files = decode_files(document)
  let groups = decode_groups(document, "duplicates")
  let errors = validate_candidate_groups(files, groups)
  if errors.length() > 0 {
    return ({ "error": errors.join("；") } : Json).stringify()
  }
  ({ "groups": advise_duplicate_groups(files, groups).to_json() } : Json).stringify()
}
