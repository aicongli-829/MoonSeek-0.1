///|
/// Normalize separators at the filesystem boundary. Internal paths always use
/// forward slashes so plans are portable and easy to audit.
pub fn native_path(root : String, relative : String) -> String {
  let separator = if root.contains("\\") { "\\" } else { "/" }
  let suffix = relative.replace_all(old="/", new=separator)
  if root.has_suffix(separator) {
    root + suffix
  } else {
    root + separator + suffix
  }
}

///|
/// Read UTF-8 text using MoonBit's native asynchronous filesystem.
pub async fn read_text(path : String) -> String {
  @fs.read_file(path).text()
}

///|
/// Write a synced UTF-8 file, creating or truncating it as requested.
pub async fn write_text(path : String, content : String) -> Unit {
  @fs.write_file(path, content, create_mode=CreateOrTruncate, sync=Full)
}

///|
/// Resolve and validate the user-selected workspace root.
pub async fn resolve_root(input : String) -> String {
  let root = @fs.realpath(input)
  guard @fs.kind(root, follow_symlink=false) is Directory else {
    fail("请选择文件夹")
  }
  let trimmed = root.trim_end(chars=['/', '\\'])
  guard trimmed.length() > 2 else {
    fail("请选具体文件夹，不要选整个磁盘")
  }
  trimmed.to_owned()
}

///|
/// A native smoke test also exercises import linkage to the deterministic core.
pub fn core_probe() -> String {
  @core.configuration_defaults_json("{}")
}
