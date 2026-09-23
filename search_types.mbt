///|
let document_extensions : Array[String] = [
  "txt", "md", "markdown", "pdf", "doc", "docx", "odt", "rtf", "tex", "epub", "mobi",
  "pages",
]

///|
let spreadsheet_extensions : Array[String] = [
  "csv", "tsv", "xls", "xlsx", "ods", "numbers",
]

///|
let presentation_extensions : Array[String] = ["ppt", "pptx", "odp", "key"]

///|
let image_extensions : Array[String] = [
  "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "ico", "tif", "tiff", "heic",
  "avif", "raw", "psd", "ai",
]

///|
let audio_extensions : Array[String] = [
  "mp3", "wav", "flac", "aac", "ogg", "m4a", "wma", "opus", "mid", "midi",
]

///|
let video_extensions : Array[String] = [
  "mp4", "mkv", "mov", "avi", "webm", "wmv", "flv", "m4v", "mpeg", "mpg",
]

///|
let archive_extensions : Array[String] = [
  "zip", "7z", "rar", "tar", "gz", "bz2", "xz", "tgz", "zst", "cab", "iso",
]

///|
let source_extensions : Array[String] = [
  "mbt", "js", "mjs", "cjs", "ts", "tsx", "jsx", "py", "pyi", "rs", "go", "java",
  "kt", "kts", "c", "cc", "cpp", "h", "hpp", "cs", "fs", "fsx", "vb", "swift", "dart",
  "rb", "php", "lua", "r", "jl", "scala", "clj", "cljs", "ex", "exs", "erl", "hrl",
  "hs", "lhs", "ml", "mli", "vue", "svelte", "astro", "sol", "asm", "s",
]

///|
let web_extensions : Array[String] = [
  "html", "htm", "css", "scss", "sass", "less", "wasm",
]

///|
let data_extensions : Array[String] = [
  "json", "jsonl", "xml", "yaml", "yml", "toml", "ini", "cfg", "conf", "sql", "db",
  "sqlite", "sqlite3", "parquet", "avro",
]

///|
let script_extensions : Array[String] = [
  "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd", "vbs", "awk", "sed",
]

///|
let executable_extensions : Array[String] = [
  "exe", "msi", "app", "apk", "deb", "rpm", "dmg", "pkg", "appimage", "dll", "so",
  "dylib",
]

///|
let font_extensions : Array[String] = ["ttf", "otf", "woff", "woff2", "eot"]

///|
fn canonical_file_category(value : String) -> String {
  match value.trim().to_owned().to_lower() {
    "doc" | "docs" | "text" | "document" | "documents" => "document"
    "sheet" | "sheets" | "spreadsheet" | "spreadsheets" => "spreadsheet"
    "slide" | "slides" | "presentation" | "presentations" => "presentation"
    "photo" | "photos" | "picture" | "pictures" | "image" | "images" => "image"
    "music" | "sound" | "audio" => "audio"
    "movie" | "movies" | "video" | "videos" => "video"
    "compressed" | "archive" | "archives" => "archive"
    "source" | "sources" | "code" => "code"
    "web" => "web"
    "config" | "configuration" | "database" | "data" => "data"
    "shell" | "script" | "scripts" => "script"
    "binary" | "binaries" | "program" | "app" | "executable" => "executable"
    "font" | "fonts" => "font"
    "other" | "file" | "files" => "other"
    category => category
  }
}

///|
pub fn file_category(extension : String) -> String {
  let extension = extension.trim().trim_start(chars=['.']).to_owned().to_lower()
  if document_extensions.contains(extension) {
    "document"
  } else if spreadsheet_extensions.contains(extension) {
    "spreadsheet"
  } else if presentation_extensions.contains(extension) {
    "presentation"
  } else if image_extensions.contains(extension) {
    "image"
  } else if audio_extensions.contains(extension) {
    "audio"
  } else if video_extensions.contains(extension) {
    "video"
  } else if archive_extensions.contains(extension) {
    "archive"
  } else if source_extensions.contains(extension) {
    "code"
  } else if web_extensions.contains(extension) {
    "web"
  } else if data_extensions.contains(extension) {
    "data"
  } else if script_extensions.contains(extension) {
    "script"
  } else if executable_extensions.contains(extension) {
    "executable"
  } else if font_extensions.contains(extension) {
    "font"
  } else {
    "other"
  }
}

///|
fn category_matches(extension : String, categories : Array[String]) -> Bool {
  categories.length() == 0 || categories.contains(file_category(extension))
}

///|
fn category_row(name : String, extensions : Array[String]) -> Json {
  { "name": name, "extensions": extensions.to_json() }
}

///|
pub fn file_type_catalog_json() -> String {
  (
    {
      "categories": [
        category_row("document", document_extensions),
        category_row("spreadsheet", spreadsheet_extensions),
        category_row("presentation", presentation_extensions),
        category_row("image", image_extensions),
        category_row("audio", audio_extensions),
        category_row("video", video_extensions),
        category_row("archive", archive_extensions),
        category_row("code", source_extensions),
        category_row("web", web_extensions),
        category_row("data", data_extensions),
        category_row("script", script_extensions),
        category_row("executable", executable_extensions),
        category_row("font", font_extensions),
      ].to_json(),
    } : Json).stringify()
}
