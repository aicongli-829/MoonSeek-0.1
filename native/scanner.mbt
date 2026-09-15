///|
priv struct NativeFile {
  path : String
  name : String
  month : String
  size : Int64
  modified_seconds : Int64
  modified_nanos : Int
  sha256 : String
  data : Bytes
}

///|
fn NativeFile::public_json(self : NativeFile) -> Json {
  {
    "path": self.path,
    "name": self.name,
    "month": self.month,
    "size": self.size.to_string(),
    "hash": self.sha256,
    "fingerprint": {
      "size": self.size.to_string(),
      "mtimeSeconds": self.modified_seconds.to_string(),
      "mtimeNanos": self.modified_nanos,
      "sha256": self.sha256,
    },
  }
}

///|
fn normalized_extensions(options : Json) -> Array[String] {
  json_strings(options, "extensions")
  .map(item => item.trim().trim_start(chars=['.']).to_owned().to_lower())
  .filter(item => item != "")
}

///|
fn ignored_relative(relative : String, exclusions : Array[String]) -> Bool {
  let lower = clean_relative(relative).to_lower()
  reserved_path(lower) ||
  exclusions.any(item => lower == item || lower.has_prefix(item + "/"))
}

///|
fn extension_of(name : String) -> String {
  match name.rev_find(".") {
    Some(index) if index + 1 < name.length() =>
      name[index + 1:].to_owned().to_lower()
    _ => ""
  }
}

///|
async fn read_stable_file(path : String, relative : String) -> NativeFile {
  let before_size = @fs.file_size(path)
  let (before_seconds, before_nanos) = @fs.mtime(path, follow_symlink=false)
  let data = @fs.read_file(path).binary()
  let after_size = @fs.file_size(path)
  let (after_seconds, after_nanos) = @fs.mtime(path, follow_symlink=false)
  guard before_size == after_size &&
    before_seconds == after_seconds &&
    before_nanos == after_nanos else {
    fail("文件扫描期间发生变化")
  }
  {
    path: relative,
    name: base_name(relative),
    month: month_from_epoch(after_seconds),
    size: after_size,
    modified_seconds: after_seconds,
    modified_nanos: after_nanos,
    sha256: sha256(data),
    data,
  }
}

///|
async fn scan_document(root : String, options : Json) -> Json {
  let recursive = json_bool(options, "recursive", true)
  let hidden = json_bool(options, "hidden", false)
  let extensions = normalized_extensions(options)
  let exclusions = json_strings(options, "exclude")
    .map(clean_relative)
    .map(String::to_lower)
  let files : Array[NativeFile] = []
  let occupied : Array[String] = []
  let directories : Array[String] = []
  let warnings : Array[String] = []
  @fs.walk(
    root,
    max_concurrency=1,
    exclude=path => {
      let relative = relative_from(root, path)
      relative != "" && (!recursive || ignored_relative(relative, exclusions))
    },
    (directory, names) => {
      for name in names {
        let full = native_path(directory, name)
        let relative = relative_from(root, full)
        occupied.push(relative)
        let kind = @fs.kind(full, follow_symlink=false) catch {
          error => {
            warnings.push(
              relative + "：无法读取类型（" + error.to_string() + "）",
            )
            continue
          }
        }
        match kind {
          Directory => directories.push(relative)
          SymLink => warnings.push(relative + "：已跳过链接")
          Regular => {
            if ignored_relative(relative, exclusions) ||
              (!hidden && name.has_prefix(".")) {
              continue
            }
            if extensions.length() > 0 &&
              !extensions.contains(extension_of(name)) {
              continue
            }
            guard files.length() < 10000 else {
              fail("每次最多处理 10,000 个文件，请缩小范围")
            }
            files.push(read_stable_file(full, relative)) catch {
              error => warnings.push(relative + "：" + error.to_string())
            }
          }
          _ => ()
        }
      }
    },
  )
  files.sort_by((left, right) => @core.natural_compare(left.path, right.path))
  let candidates : Map[String, Array[Int]] = Map([])
  for index, file in files {
    let key = file.size.to_string() + ":" + file.sha256
    match candidates.get(key) {
      Some(group) => group.push(index)
      None => candidates[key] = [index]
    }
  }
  let duplicates : Array[Json] = []
  for _, indices in candidates {
    if indices.length() < 2 {
      continue
    }
    let clusters : Array[Array[Int]] = []
    for index in indices {
      match
        clusters
        .iter()
        .find_first(cluster => files[cluster[0]].data == files[index].data) {
        Some(cluster) => cluster.push(index)
        None => clusters.push([index])
      }
    }
    for cluster in clusters {
      if cluster.length() > 1 {
        duplicates.push(cluster.map(index => files[index].path).to_json())
      }
    }
  }
  {
    "files": files.map(NativeFile::public_json).to_json(),
    "occupied": occupied.to_json(),
    "directories": directories.to_json(),
    "duplicates": duplicates.to_json(),
    "warnings": warnings.to_json(),
  }
}

///|
/// Scan one workspace and return the full inventory expected by the core.
pub async fn scan_json(root_input : String, options_source : String) -> String {
  try {
    let root = resolve_root(root_input)
    let normalized = @core.validate_options_json(options_source)
    let checked = parse_document(normalized, "设置结果")
    match json_field(checked, "error") {
      String(message) => return json_error(message)
      _ => ()
    }
    let options = json_field(checked, "options")
    let inventory = scan_document(root, options)
    ({ "root": root, "options": options, "inventory": inventory } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}
