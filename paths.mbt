///| Split on the final extension. A leading dot alone is not an extension.
pub fn split_extension(name : String) -> (String, String) {
  let mut dot = -1
  for i = 1; i < name.length(); i = i + 1 {
    if name[i] == 46 {
      dot = i
    }
  }
  if dot < 0 {
    (name, "")
  } else {
    (name[:dot].to_owned(), name[dot:].to_owned())
  }
}

///|
pub fn parent_path(value : String) -> String {
  match value.rev_split_once("/") {
    Some((parent, _)) => parent.to_owned()
    None => ""
  }
}

///|
pub fn base_name(value : String) -> String {
  match value.rev_split_once("/") {
    Some((_, name)) => name.to_owned()
    None => value
  }
}

///|
pub fn join_path(folder : String, name : String) -> String {
  if folder == "" { name } else { folder + "/" + name }
}

///| Portable filename diagnostics, including Windows device names.
pub fn filename_error(name : String) -> String? {
  if name == "" || name == "." || name == ".." {
    return Some("文件名不能为空或为 .、..")
  }
  if name.length() > 180 {
    return Some("文件名超过首版的 180 字符限制")
  }
  for ch in name.iter() {
    if ch.to_int() < 32 || "<>:\"/\\|?*".contains(ch.to_string()) {
      return Some("文件名包含不允许的字符")
    }
  }
  if name.has_suffix(" ") || name.has_suffix(".") {
    return Some("文件名不能以空格或点结尾")
  }
  let stem = name.split(".").to_array()[0].to_owned().to_upper()
  let reserved = [
    "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5",
    "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5",
    "LPT6", "LPT7", "LPT8", "LPT9",
  ]
  if reserved.contains(stem) {
    return Some("Windows 保留设备名")
  }
  None
}

///|
pub fn path_error(value : String) -> String? {
  if value == "" || value.has_prefix("/") || value.contains("\\") {
    return Some("必须使用安全的相对路径")
  }
  if value.length() > 220 {
    return Some("相对路径过长，请缩短目录或文件名")
  }
  for part in value.split("/") {
    let piece = part.to_owned()
    if filename_error(piece) is Some(error) {
      return Some(error)
    }
    if [".git", ".filenest", "node_modules", ".tools", "_build", "target"].contains(piece.to_lower()) {
      return Some("不能写入保留目录")
    }
  }
  None
}

///| Suffix before the final extension; used only for conflict resolution.
pub fn numbered_path(value : String, number : Int) -> String {
  let (stem, ext) = split_extension(base_name(value))
  join_path(parent_path(value), stem + " (" + number.to_string() + ")" + ext)
}
