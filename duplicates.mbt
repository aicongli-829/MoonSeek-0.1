///|
/// Candidate duplicate groups are identified by exact byte length and a
/// cryptographic digest supplied by the host. The host still performs a final
/// byte-for-byte comparison before presenting any group to the user.
pub fn duplicate_candidates(files : Array[FileEntry]) -> Array[Array[String]] {
  let buckets : Map[String, Array[String]] = Map([])
  let order = []
  for file in files {
    if file.path == "" ||
      file.hash == "" ||
      normalize_decimal(file.size) is None {
      continue
    }
    let key = normalize_decimal(file.size).unwrap() + ":" + file.hash.to_lower()
    if !buckets.contains(key) {
      buckets[key] = []
      order.push(key)
    }
    buckets[key].push(file.path)
  }
  let output = []
  for key in order {
    let group = buckets[key]
    if group.length() > 1 {
      output.push(group.copy())
    }
  }
  output
}

///|
/// Stable group ordering makes CLI output and reports reproducible even when
/// the operating system returns directory entries in a different order.
pub fn sort_duplicate_groups(
  groups : Array[Array[String]],
) -> Array[Array[String]] {
  let result = groups.map(group => {
    let copy = group.copy()
    copy.sort_by(natural_compare)
    copy
  })
  result.sort_by((left, right) => {
    if left.length() == 0 && right.length() == 0 {
      0
    } else if left.length() == 0 {
      -1
    } else if right.length() == 0 {
      1
    } else {
      natural_compare(left[0], right[0])
    }
  })
  result
}

///|
/// Validate candidate groups before the host spends time reading their bytes.
pub fn validate_candidate_groups(
  files : Array[FileEntry],
  groups : Array[Array[String]],
) -> Array[String] {
  let errors = []
  let by_path : Map[String, FileEntry] = Map([])
  for file in files {
    if by_path.contains(file.path) {
      errors.push("扫描结果包含重复路径：" + file.path)
    } else {
      by_path[file.path] = file
    }
  }
  let seen : Map[String, Bool] = Map([])
  for group in groups {
    if group.length() < 2 {
      errors.push("重复候选组至少需要两个文件")
      continue
    }
    let first = by_path.get(group[0])
    if first is None {
      errors.push("重复候选文件不在清单中：" + group[0])
      continue
    }
    for item in group {
      if seen.contains(item) {
        errors.push("文件出现在多个重复候选组：" + item)
      }
      seen[item] = true
      match by_path.get(item) {
        None => errors.push("重复候选文件不在清单中：" + item)
        Some(current) =>
          if normalize_decimal(current.size) !=
            normalize_decimal(first.unwrap().size) ||
            current.hash.to_lower() != first.unwrap().hash.to_lower() {
            errors.push("重复候选组的大小或摘要不一致")
          }
      }
    }
  }
  errors
}

///|
/// JavaScript boundary for the first phase of duplicate detection.
pub fn duplicate_candidates_json(input : String) -> String {
  let document = @json.parse(input) catch {
    _ =>
      return ({ "error": "重复检查输入不是合法 JSON" } : Json).stringify()
  }
  let files = decode_files(document)
  if files.length() > 10000 {
    return ({ "error": "每次最多分析 10,000 个文件" } : Json).stringify()
  }
  let groups = sort_duplicate_groups(duplicate_candidates(files))
  let errors = validate_candidate_groups(files, groups)
  if errors.length() > 0 {
    return ({ "error": errors.join("；") } : Json).stringify()
  }
  ({ "groups": groups.to_json() } : Json).stringify()
}
