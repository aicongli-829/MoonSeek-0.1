///|
/// Aggregated extension statistics used by CLI and API consumers.
pub(all) struct ExtensionStatistic {
  extension : String
  count : Int
  bytes : String
  percent : Int
} derive(Eq, Debug, ToJson)

///|
/// Aggregated built-in category statistics.
pub(all) struct CategoryStatistic {
  category : String
  count : Int
  bytes : String
  percent : Int
} derive(Eq, Debug, ToJson)

///|
/// Top-level folder distribution helps reveal a cluttered root directory.
pub(all) struct FolderStatistic {
  folder : String
  count : Int
  bytes : String
  percent : Int
} derive(Eq, Debug, ToJson)

///|
/// Size bands are fixed so reports can be compared between scans.
pub(all) struct SizeBandStatistic {
  band : String
  count : Int
  bytes : String
  percent : Int
} derive(Eq, Debug, ToJson)

///|
/// Largest files are returned separately from aggregates because they are
/// often the quickest way to understand unexpected disk usage.
pub(all) struct LargeFileStatistic {
  path : String
  size : String
  category : String
} derive(Eq, Debug, ToJson)

///|
/// Complete deterministic analysis of one inventory.
pub(all) struct InventoryAnalysis {
  total_files : Int
  total_bytes : String
  duplicate_groups : Int
  duplicate_files : Int
  reclaimable_bytes : String
  root_files : Int
  deepest_level : Int
  hidden_files : Int
  extensions : Array[ExtensionStatistic]
  categories : Array[CategoryStatistic]
  folders : Array[FolderStatistic]
  size_bands : Array[SizeBandStatistic]
  largest_files : Array[LargeFileStatistic]
  duplicate_advice : Array[DuplicateAdvice]
  recommendations : Array[String]
} derive(Eq, Debug)

///|
/// Canonical extension label for reports. Compound archives still use their
/// final suffix because that matches scan filters and rename behavior.
pub fn analysis_extension(name : String) -> String {
  let (_, extension) = split_extension(name)
  if extension == "" {
    "（无扩展名）"
  } else {
    extension.to_lower()
  }
}

///|
/// The first directory segment, or a visible label for loose root files.
pub fn analysis_folder(path : String) -> String {
  match path.split_once("/") {
    Some((folder, _)) => folder.to_owned()
    None => "（根目录）"
  }
}

///|
/// One-based nesting level where root files are level zero.
pub fn analysis_depth(path : String) -> Int {
  let mut depth = 0
  for character in path.iter() {
    if character == '/' {
      depth = depth + 1
    }
  }
  depth
}

///|
/// Fixed, human-readable size band selected with exact decimal comparison.
pub fn analysis_size_band(size : String) -> String {
  let normalized = normalize_decimal(size).unwrap_or("0")
  if normalized == "0" {
    "空文件"
  } else if decimal_compare(normalized, "1048576") < 0 {
    "小于 1 MiB"
  } else if decimal_compare(normalized, "104857600") < 0 {
    "1–100 MiB"
  } else if decimal_compare(normalized, "1073741824") < 0 {
    "100 MiB–1 GiB"
  } else {
    "至少 1 GiB"
  }
}

///|
/// Increase a count and decimal-byte total without converting file sizes to
/// JavaScript numbers or platform-sized integers.
fn analysis_accumulate(
  counts : Map[String, Int],
  sizes : Map[String, String],
  key : String,
  size : String,
) -> Unit {
  counts[key] = counts.get(key).unwrap_or(0) + 1
  sizes[key] = decimal_add(sizes.get(key).unwrap_or("0"), size)
}

///|
/// Sort labels by count, byte size and natural name for stable reports.
fn analysis_keys(
  counts : Map[String, Int],
  sizes : Map[String, String],
  order : Array[String],
) -> Array[String] {
  let keys = order.copy()
  keys.sort_by((left, right) => {
    let count_order = counts[right] - counts[left]
    if count_order != 0 {
      count_order
    } else {
      let size_order = decimal_compare(sizes[right], sizes[left])
      if size_order != 0 {
        size_order
      } else {
        natural_compare(left, right)
      }
    }
  })
  keys
}

///|
/// Accumulate labels while retaining first-seen order for deterministic ties.
fn analysis_record(
  counts : Map[String, Int],
  sizes : Map[String, String],
  order : Array[String],
  key : String,
  size : String,
) -> Unit {
  if !counts.contains(key) {
    order.push(key)
  }
  analysis_accumulate(counts, sizes, key, size)
}

///|
/// Build extension rows with percentage of file count.
fn extension_statistics(
  counts : Map[String, Int],
  sizes : Map[String, String],
  order : Array[String],
  total : Int,
) -> Array[ExtensionStatistic] {
  analysis_keys(counts, sizes, order).map(key => {
    extension: key,
    count: counts[key],
    bytes: sizes[key],
    percent: if total == 0 {
      0
    } else {
      counts[key] * 100 / total
    },
  })
}

///|
/// Build category rows with percentage of file count.
fn category_statistics(
  counts : Map[String, Int],
  sizes : Map[String, String],
  order : Array[String],
  total : Int,
) -> Array[CategoryStatistic] {
  analysis_keys(counts, sizes, order).map(key => {
    category: key,
    count: counts[key],
    bytes: sizes[key],
    percent: if total == 0 {
      0
    } else {
      counts[key] * 100 / total
    },
  })
}

///|
/// Build top-folder rows with percentage of file count.
fn folder_statistics(
  counts : Map[String, Int],
  sizes : Map[String, String],
  order : Array[String],
  total : Int,
) -> Array[FolderStatistic] {
  analysis_keys(counts, sizes, order).map(key => {
    folder: key,
    count: counts[key],
    bytes: sizes[key],
    percent: if total == 0 {
      0
    } else {
      counts[key] * 100 / total
    },
  })
}

///|
/// Size bands retain their logical order instead of being sorted by count.
fn size_band_statistics(
  counts : Map[String, Int],
  sizes : Map[String, String],
  total : Int,
) -> Array[SizeBandStatistic] {
  let bands = [
    "空文件", "小于 1 MiB", "1–100 MiB", "100 MiB–1 GiB", "至少 1 GiB",
  ]
  bands.map(band => {
    band,
    count: counts.get(band).unwrap_or(0),
    bytes: sizes.get(band).unwrap_or("0"),
    percent: if total == 0 {
      0
    } else {
      counts.get(band).unwrap_or(0) * 100 / total
    },
  })
}

///|
/// Return at most ten largest files with natural path ordering for equal sizes.
pub fn analysis_largest_files(
  files : Array[FileEntry],
) -> Array[LargeFileStatistic] {
  let sorted = files.copy()
  sorted.sort_by((left, right) => {
    let by_size = decimal_compare(right.size, left.size)
    if by_size != 0 {
      by_size
    } else {
      natural_compare(left.path, right.path)
    }
  })
  let result = []
  for index = 0; index < sorted.length() && index < 10; index = index + 1 {
    let file = sorted[index]
    result.push({
      path: file.path,
      size: normalize_decimal(file.size).unwrap_or("0"),
      category: file_category(file.name),
    })
  }
  result
}

///|
/// Count all duplicate members rather than only reclaimable copies.
pub fn analysis_duplicate_file_count(groups : Array[Array[String]]) -> Int {
  let unique : Map[String, Bool] = Map([])
  for group in groups {
    for item in group {
      unique[item] = true
    }
  }
  unique.length()
}

///|
/// Generate concise actions based on observable inventory facts. Suggestions
/// never mutate options and remain useful to both the web UI and CLI.
pub fn analysis_recommendations(
  total : Int,
  root_files : Int,
  deepest : Int,
  hidden : Int,
  extension_count : Int,
  other_count : Int,
  empty_count : Int,
  duplicate_groups : Int,
  reclaimable : String,
) -> Array[String] {
  let output = []
  if total == 0 {
    output.push("当前范围没有可分析的普通文件。")
    return output
  }
  if duplicate_groups > 0 && reclaimable != "0" {
    output.push(
      "发现可隔离的重复副本；请逐组保留一份后再执行整理。",
    )
  }
  if root_files * 100 / total >= 60 && root_files >= 10 {
    output.push(
      "大部分文件直接堆在根目录，适合先按文件类型或月份分类。",
    )
  }
  if extension_count >= 12 {
    output.push(
      "文件格式较分散，可为高频扩展名建立自定义分类规则。",
    )
  }
  if other_count * 100 / total >= 25 {
    output.push(
      "“其他”类型占比较高，建议查看扩展名统计并补充自定义分类。",
    )
  }
  if empty_count > 0 {
    output.push(
      "存在空文件，整理前可确认它们是否仍有保留价值。",
    )
  }
  if deepest >= 6 {
    output.push(
      "目录层级较深，批量重命名时请关注完整目标路径。",
    )
  }
  if hidden > 0 {
    output.push(
      "扫描包含隐藏文件；执行前请确认这些文件也需要整理。",
    )
  }
  if output.length() == 0 {
    output.push(
      "当前文件分布较整齐，可从预览中选择需要的命名规则。",
    )
  }
  output
}

///|
/// Analyze inventory metadata and confirmed duplicate groups without any I/O.
pub fn analyze_inventory(
  files : Array[FileEntry],
  duplicate_groups : Array[Array[String]],
) -> InventoryAnalysis {
  let extension_counts : Map[String, Int] = Map([])
  let extension_sizes : Map[String, String] = Map([])
  let extension_order = []
  let category_counts : Map[String, Int] = Map([])
  let category_sizes : Map[String, String] = Map([])
  let category_order = []
  let folder_counts : Map[String, Int] = Map([])
  let folder_sizes : Map[String, String] = Map([])
  let folder_order = []
  let band_counts : Map[String, Int] = Map([])
  let band_sizes : Map[String, String] = Map([])
  let mut total_bytes = "0"
  let mut root_files = 0
  let mut deepest = 0
  let mut hidden = 0
  for file in files {
    let size = normalize_decimal(file.size).unwrap_or("0")
    total_bytes = decimal_add(total_bytes, size)
    let extension = analysis_extension(file.name)
    let category = file_category(file.name)
    let folder = analysis_folder(file.path)
    let band = analysis_size_band(size)
    analysis_record(
      extension_counts, extension_sizes, extension_order, extension, size,
    )
    analysis_record(
      category_counts, category_sizes, category_order, category, size,
    )
    analysis_record(folder_counts, folder_sizes, folder_order, folder, size)
    analysis_accumulate(band_counts, band_sizes, band, size)
    let depth = analysis_depth(file.path)
    if depth == 0 {
      root_files = root_files + 1
    }
    if depth > deepest {
      deepest = depth
    }
    if file.name.has_prefix(".") {
      hidden = hidden + 1
    }
  }
  let total = files.length()
  let reclaimable = duplicate_reclaimable_bytes(files, duplicate_groups)
  let other_count = category_counts.get("其他").unwrap_or(0)
  let empty_count = band_counts.get("空文件").unwrap_or(0)
  {
    total_files: total,
    total_bytes,
    duplicate_groups: duplicate_groups.length(),
    duplicate_files: analysis_duplicate_file_count(duplicate_groups),
    reclaimable_bytes: reclaimable,
    root_files,
    deepest_level: deepest,
    hidden_files: hidden,
    extensions: extension_statistics(
      extension_counts, extension_sizes, extension_order, total,
    ),
    categories: category_statistics(
      category_counts, category_sizes, category_order, total,
    ),
    folders: folder_statistics(folder_counts, folder_sizes, folder_order, total),
    size_bands: size_band_statistics(band_counts, band_sizes, total),
    largest_files: analysis_largest_files(files),
    duplicate_advice: advise_duplicate_groups(files, duplicate_groups),
    recommendations: analysis_recommendations(
      total,
      root_files,
      deepest,
      hidden,
      extension_counts.length(),
      other_count,
      empty_count,
      duplicate_groups.length(),
      reclaimable,
    ),
  }
}

///|
/// Camel-case JSON contract consumed by Node and suitable for saved reports.
fn inventory_analysis_json(analysis : InventoryAnalysis) -> Json {
  {
    "schemaVersion": 1,
    "totalFiles": analysis.total_files,
    "totalBytes": analysis.total_bytes,
    "duplicateGroups": analysis.duplicate_groups,
    "duplicateFiles": analysis.duplicate_files,
    "reclaimableBytes": analysis.reclaimable_bytes,
    "rootFiles": analysis.root_files,
    "deepestLevel": analysis.deepest_level,
    "hiddenFiles": analysis.hidden_files,
    "extensions": analysis.extensions.to_json(),
    "categories": analysis.categories.to_json(),
    "folders": analysis.folders.to_json(),
    "sizeBands": analysis.size_bands.to_json(),
    "largestFiles": analysis.largest_files.to_json(),
    "duplicateAdvice": analysis.duplicate_advice.to_json(),
    "recommendations": analysis.recommendations.to_json(),
  }
}

///|
/// JavaScript boundary for inventory analysis.
pub fn analyze_inventory_json(input : String) -> String {
  let document = @json.parse(input) catch {
    _ =>
      return ({ "error": "分析输入不是合法 JSON" } : Json).stringify()
  }
  let files = decode_files(document)
  if files.length() > 10000 {
    return ({ "error": "每次最多分析 10,000 个文件" } : Json).stringify()
  }
  for file in files {
    if file.path == "" ||
      file.name == "" ||
      normalize_decimal(file.size) is None {
      return (
        { "error": "文件清单包含无效路径、名称或大小" } : Json).stringify()
    }
  }
  let duplicates = decode_groups(document, "duplicates")
  let selection_errors = validate_candidate_groups(files, duplicates)
  if selection_errors.length() > 0 {
    return ({ "error": selection_errors.join("；") } : Json).stringify()
  }
  inventory_analysis_json(analyze_inventory(files, duplicates)).stringify()
}
