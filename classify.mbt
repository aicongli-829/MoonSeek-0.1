///|
/// Human-readable default categories; filenames are matched case-insensitively.
pub fn file_category(name : String) -> String {
  let (_, ext) = split_extension(name)
  let suffix = ext.to_lower()
  if [".pdf", ".doc", ".docx", ".txt", ".md", ".rtf", ".odt"].contains(suffix) {
    "文档"
  } else if [".xls", ".xlsx", ".csv", ".tsv", ".ods"].contains(suffix) {
    "表格"
  } else if [".ppt", ".pptx", ".odp", ".key"].contains(suffix) {
    "演示文稿"
  } else if [
      ".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg", ".bmp", ".heic", ".tif",
    ].contains(suffix) {
    "图片"
  } else if [".mp4", ".mov", ".mkv", ".avi", ".webm", ".m4v"].contains(suffix) {
    "视频"
  } else if [".mp3", ".wav", ".flac", ".m4a", ".ogg", ".aac"].contains(suffix) {
    "音频"
  } else if [".zip", ".7z", ".rar", ".tar", ".gz", ".bz2", ".xz"].contains(
      suffix,
    ) {
    "压缩包"
  } else if [".exe", ".msi", ".dmg", ".pkg", ".deb", ".apk"].contains(suffix) {
    "安装包"
  } else {
    "其他"
  }
}

///|
pub fn custom_category(name : String, rules : Array[CategoryRule]) -> String {
  let (_, ext) = split_extension(name)
  for rule in rules {
    let value = rule.value.to_lower()
    if rule.kind == "keyword" && name.to_lower().contains(value) {
      return rule.folder
    }
    if rule.kind == "extension" {
      for item in value.split(",") {
        let key = item.trim().to_owned()
        let suffix = if key.has_prefix(".") { key } else { "." + key }
        if ext.to_lower() == suffix {
          return rule.folder
        }
      }
    }
  }
  "其他"
}

///|
pub fn destination_folder(file : FileEntry, options : Options) -> String {
  match options.classify {
    "none" => parent_path(file.path)
    "month" => file.month
    "type_month" => join_path(file_category(file.name), file.month)
    "custom" => custom_category(file.name, options.categories)
    _ => file_category(file.name)
  }
}
