///|
let reserved_directories : Array[String] = [
  ".git", ".filenest", ".tools", ".mooncakes", "_build", "target", "node_modules",
  "重复文件隔离",
]

///|
fn slash_path(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
fn clean_relative(path : String) -> String {
  slash_path(path).trim(chars=['/']).to_owned()
}

///|
fn base_name(path : String) -> String {
  let clean = slash_path(path)
  match clean.rev_find("/") {
    Some(index) => clean[index + 1:].to_owned()
    None => clean
  }
}

///|
fn parent_name(path : String) -> String {
  let clean = slash_path(path)
  match clean.rev_find("/") {
    Some(index) => clean[:index].to_owned()
    None => ""
  }
}

///|
fn relative_from(root : String, path : String) -> String {
  let normalized_root = slash_path(root).trim_end(chars=['/']).to_owned()
  let normalized = slash_path(path)
  if normalized == normalized_root {
    ""
  } else if normalized.has_prefix(normalized_root + "/") {
    normalized[normalized_root.length() + 1:].to_owned()
  } else {
    ""
  }
}

///|
fn reserved_path(relative : String) -> Bool {
  clean_relative(relative)
  .split("/")
  .any(piece => reserved_directories.contains(piece.to_owned().to_lower()))
}

///|
fn validate_relative(
  relative : String,
  internal? : Bool = false,
) -> Array[String] raise {
  let clean = slash_path(relative)
  guard clean != "" && !clean.has_prefix("/") else {
    fail("不安全的相对路径")
  }
  guard !(clean.length() >= 2 && clean[1] == ':') else {
    fail("不安全的相对路径")
  }
  let pieces = [ for piece in clean.split("/") => piece.to_owned() ]
  guard !pieces.any(piece => piece == "" || piece == "." || piece == "..") else {
    fail("路径不能包含空段、. 或 ..")
  }
  if !internal &&
    pieces.any(piece => reserved_directories.contains(piece.to_lower())) {
    fail("不能操作保留目录")
  }
  pieces
}

///|
pub async fn safe_native_path(
  root : String,
  relative : String,
  internal? : Bool = false,
) -> String {
  let pieces = validate_relative(relative, internal~)
  let mut current = root
  for index, piece in pieces {
    current = native_path(current, piece)
    if @fs.exists(current) {
      let kind = @fs.kind(current, follow_symlink=false)
      guard kind != SymLink else {
        fail("不处理符号链接或目录联接")
      }
      if index < pieces.length() - 1 {
        guard kind is Directory else { fail("父路径不是文件夹") }
      }
    }
  }
  current
}

///|
async fn ensure_parent(path : String) -> Unit {
  let parent = parent_name(path)
  if parent != "" && !@fs.exists(parent) {
    @fs.mkdir(parent, recursive=true)
  }
}
