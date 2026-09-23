///|
let searchable_extensions : Array[String] = [
  "txt", "md", "markdown", "mbt", "json", "jsonl", "toml", "yaml", "yml", "ini",
  "cfg", "conf", "log", "csv", "tsv", "html", "htm", "css", "js", "mjs", "cjs", "ts",
  "tsx", "jsx", "py", "rs", "go", "java", "kt", "c", "cc", "cpp", "h", "hpp", "sh",
  "bash", "zsh", "ps1", "xml", "sql",
]

///|
let search_excluded_directories : Array[String] = [
  ".git", ".svn", ".hg", ".moonseek", "_build", "node_modules", "target", "dist",
  ".cache", ".idea", ".vscode", "__pycache__",
]

///|
fn search_extension(name : String) -> String {
  match name.rev_find(".") {
    Some(index) if index + 1 < name.length() =>
      name[index + 1:].to_owned().to_lower()
    _ => ""
  }
}

///|
fn search_included_extension(
  extension : String,
  configured : Array[String],
) -> Bool {
  if configured.length() > 0 {
    configured.contains(extension)
  } else {
    true
  }
}

///|
fn search_content_extension(extension : String) -> Bool {
  searchable_extensions.contains(extension)
}

///|
fn search_ignored_directory(
  path : String,
  root : String,
  rules : Array[SearchIgnoreRule],
) -> Bool {
  let relative = relative_from(root, path)
  if relative == "" {
    return false
  }
  relative
  .split("/")
  .any(piece => {
    search_excluded_directories.contains(piece.to_owned().to_lower())
  }) ||
  search_path_ignored(relative, true, rules)
}

///|
async fn resolve_search_root(input : String) -> String {
  let root = @fs.realpath(input)
  guard @fs.kind(root, follow_symlink=false) is Directory else {
    fail("choose a directory to index")
  }
  let trimmed = root.trim_end(chars=['/', '\\'])
  if trimmed.length() == 2 && trimmed[1] == ':' {
    trimmed.to_owned() + "\\"
  } else {
    trimmed.to_owned()
  }
}

///|
fn previous_documents(index : Json) -> Array[Json] {
  json_array(index, "documents")
}

///|
fn previous_document_map(index : Json, root : String) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for document in previous_documents(index) {
    if json_text(document, "root", "") == root {
      result[json_text(document, "path", "")] = document
    }
  }
  result
}

///|
fn reusable_document(previous : Json, size : Int64, modified : Int64) -> Bool {
  json_int64_or(previous, "size", -1L) == size &&
  json_int64_or(previous, "modified", -1L) == modified &&
  json_array(previous, "termCounts").length() > 0
}

///|
fn configured_search_extensions(options : Json) -> Array[String] {
  json_strings(options, "extensions")
  .map(item => item.trim().trim_start(chars=['.']).to_owned().to_lower())
  .filter(item => item != "")
}

///|
async fn scan_search_documents(
  root_input : String,
  previous_index : Json,
  options : Json,
) -> Json {
  let root = resolve_search_root(root_input)
  let previous = previous_document_map(previous_index, root)
  let documents : Array[Json] = []
  for document in previous_documents(previous_index) {
    if json_text(document, "root", "") != root {
      documents.push(document)
    }
  }
  let warnings : Array[String] = []
  let extensions = configured_search_extensions(options)
  let include_hidden = json_bool(options, "hidden", false)
  let max_file_bytes = json_int64_or(
    options,
    "maxFileBytes",
    4L * 1024L * 1024L,
  ).clamp(min=1024L, max=32L * 1024L * 1024L)
  let mut indexed = 0
  let mut reused = 0
  let mut skipped = 0
  let mut content_files = 0
  let mut metadata_files = 0
  let mut total_bytes = 0L
  let ignore_rules = load_search_ignore_rules(root)
  @fs.walk(
    root,
    max_concurrency=1,
    exclude=path => search_ignored_directory(path, root, ignore_rules),
    (directory, names) => {
      for name in names {
        let full = native_path(directory, name)
        let relative = relative_from(root, full)
        let kind = @fs.kind(full, follow_symlink=false) catch {
          error => {
            warnings.push(relative + ": " + error.to_string())
            skipped = skipped + 1
            continue
          }
        }
        guard kind is Regular else { continue }
        if (!include_hidden && name.has_prefix(".")) ||
          reserved_path(relative) ||
          search_path_ignored(relative, false, ignore_rules) {
          skipped = skipped + 1
          continue
        }
        let extension = search_extension(name)
        if !search_included_extension(extension, extensions) {
          skipped = skipped + 1
          continue
        }
        let size = @fs.file_size(full) catch {
          error => {
            warnings.push(relative + ": " + error.to_string())
            skipped = skipped + 1
            continue
          }
        }
        let (modified, _) = @fs.mtime(full, follow_symlink=false) catch {
          error => {
            warnings.push(relative + ": " + error.to_string())
            skipped = skipped + 1
            continue
          }
        }
        match previous.get(relative) {
          Some(document) if reusable_document(document, size, modified) => {
            documents.push(document)
            reused = reused + 1
            if search_content_extension(extension) && size <= max_file_bytes {
              content_files = content_files + 1
            } else {
              metadata_files = metadata_files + 1
            }
            total_bytes = total_bytes + size
          }
          _ => {
            let content = if search_content_extension(extension) &&
              size <= max_file_bytes {
              @fs.read_file(full).text() catch {
                error => {
                  warnings.push(
                    relative + ": content skipped: " + error.to_string(),
                  )
                  ""
                }
              }
            } else {
              ""
            }
            if content == "" {
              metadata_files = metadata_files + 1
            } else {
              content_files = content_files + 1
            }
            documents.push({
              "id": root + "/" + relative,
              "root": root,
              "path": relative,
              "name": name,
              "extension": extension,
              "size": size.to_string(),
              "modified": modified.to_string(),
              "content": content,
            })
            indexed = indexed + 1
            total_bytes = total_bytes + size
          }
        }
        guard documents.length() <= 100000 else {
          fail("an index is limited to 100,000 text files")
        }
      }
    },
  )
  documents.sort_by((left, right) => {
    let left_key = json_text(left, "root", "") +
      "/" +
      json_text(left, "path", "")
    let right_key = json_text(right, "root", "") +
      "/" +
      json_text(right, "path", "")
    left_key.compare(right_key)
  })
  {
    "root": root,
    "documents": documents.to_json(),
    "scan": {
      "indexed": indexed,
      "reused": reused,
      "skipped": skipped,
      "contentFiles": content_files,
      "metadataFiles": metadata_files,
      "bytes": total_bytes.to_string(),
      "warnings": warnings.to_json(),
    },
  }
}
