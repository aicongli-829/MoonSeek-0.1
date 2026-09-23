///|
let reserved_directories : Array[String] = [
  ".git", ".moonseek", ".tools", ".mooncakes", "_build", "target", "node_modules",
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
    fail("unsafe relative path")
  }
  guard !(clean.length() >= 2 && clean[1] == ':') else {
    fail("unsafe relative path")
  }
  let pieces = [ for piece in clean.split("/") => piece.to_owned() ]
  guard !pieces.any(piece => piece == "" || piece == "." || piece == "..") else {
    fail("a path cannot contain empty, dot, or parent segments")
  }
  if !internal &&
    pieces.any(piece => reserved_directories.contains(piece.to_lower())) {
    fail("reserved directories cannot be accessed")
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
        fail("symbolic links and directory junctions are not supported")
      }
      if index < pieces.length() - 1 {
        guard kind is Directory else {
          fail("a parent path is not a directory")
        }
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
