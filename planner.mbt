///|
/// Build a deterministic preview. Existing paths include unselected files and
/// directories so exclusion can never implicitly authorize an overwrite.
pub fn plan(
  files : Array[FileEntry],
  occupied : Array[String],
  options : Options,
) -> Array[PlanRow] {
  let sorted = files.copy()
  sorted.sort_by((a, b) => {
    let primary = match options.sort {
      "path" => natural_compare(a.path, b.path)
      "month" => a.month.compare(b.month)
      "size" => decimal_compare(a.size, b.size)
      _ => natural_compare(a.name, b.name)
    }
    if primary == 0 {
      natural_compare(a.path, b.path)
    } else {
      primary
    }
  })
  let used : Map[String, Bool] = Map([])
  for item in occupied {
    used[item.to_lower()] = true
  }
  let output = []
  let mut sequence = options.sequence_start
  for file in sorted {
    let category = file_category(file.name)
    if options.excluded.contains(file.path) {
      output.push({
        source: file.path,
        target: file.path,
        status: "excluded",
        reason: "手动排除",
        category,
      })
      continue
    }
    let name = rename_file(
      file.name,
      options.rules,
      sequence,
      options.sequence_width,
    )
    sequence = sequence + 1
    if filename_error(name) is Some(error) {
      output.push({
        source: file.path,
        target: file.path,
        status: "invalid",
        reason: error,
        category,
      })
      continue
    }
    let folder = destination_folder(file, options)
    let is_duplicate = options.quarantine.contains(file.path)
    let mut target = if is_duplicate {
      join_path("重复文件隔离", file.path)
    } else {
      join_path(folder, name)
    }
    if is_duplicate {
      let has_keeper = files.any(other => {
        other.path != file.path &&
        other.hash != "" &&
        other.hash == file.hash &&
        other.size == file.size &&
        !options.quarantine.contains(other.path)
      })
      if !has_keeper {
        output.push({
          source: file.path,
          target,
          status: "invalid",
          reason: "每组重复文件必须保留至少一份",
          category,
        })
        continue
      }
    }
    if path_error(target) is Some(error) {
      output.push({
        source: file.path,
        target,
        status: "invalid",
        reason: error,
        category,
      })
      continue
    }
    if target == file.path {
      output.push({
        source: file.path,
        target,
        status: "unchanged",
        reason: "无需改变",
        category,
      })
      continue
    }
    if used.contains(target.to_lower()) {
      if options.conflict == "number" {
        let original = target
        let mut n = 2
        while used.contains(target.to_lower()) && n < 20000 {
          target = numbered_path(original, n)
          n = n + 1
        }
      } else {
        output.push({
          source: file.path,
          target,
          status: "conflict",
          reason: "目标名称已存在或与其他操作重复",
          category,
        })
        continue
      }
    }
    if path_error(target) is Some(error) {
      output.push({
        source: file.path,
        target,
        status: "invalid",
        reason: error,
        category,
      })
      continue
    }
    used[target.to_lower()] = true
    output.push({
      source: file.path,
      target,
      status: "ready",
      reason: if is_duplicate {
        "隔离重复副本，可撤销"
      } else {
        "分类 / 重命名"
      },
      category,
    })
  }
  output
}
