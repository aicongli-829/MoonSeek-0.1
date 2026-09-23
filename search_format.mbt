///|
fn rounded_decimal(value : Double, digits : Int) -> String {
  let factor = match digits {
    0 => 1.0
    1 => 10.0
    2 => 100.0
    _ => 1000.0
  }
  let rounded = (@math.round(value * factor) / factor).to_string()
  if rounded.has_suffix(".0") {
    rounded[:rounded.length() - 2].to_owned()
  } else {
    rounded
  }
}

///|
fn format_file_size(bytes : Int64) -> String {
  let safe = bytes.max(0L)
  if safe < 1024L {
    safe.to_string() + (if safe == 1L { " byte" } else { " bytes" })
  } else if safe < 1024L * 1024L {
    rounded_decimal(safe.to_double() / 1024.0, 1) + " KiB"
  } else if safe < 1024L * 1024L * 1024L {
    rounded_decimal(safe.to_double() / (1024.0 * 1024.0), 1) + " MiB"
  } else if safe < 1024L * 1024L * 1024L * 1024L {
    rounded_decimal(safe.to_double() / (1024.0 * 1024.0 * 1024.0), 2) + " GiB"
  } else {
    rounded_decimal(safe.to_double() / (1024.0 * 1024.0 * 1024.0 * 1024.0), 2) +
    " TiB"
  }
}

///|
fn file_match_kind(result : RankedDocument, document : Json) -> String {
  let name = search_text(document, "name", "").to_lower()
  if result.matched.any(term => name.contains(term)) {
    "filename"
  } else if result.score >= 5.0 && result.matched.length() == 0 {
    "fuzzy filename"
  } else if result.matched.length() > 0 {
    "content"
  } else {
    "filter"
  }
}

///|
pub fn format_file_size_json(source : String) -> String {
  try {
    let request = search_parse(source, "format request")
    let bytes = search_int64(request, "bytes", 0L)
    ({ "bytes": bytes.to_string(), "label": format_file_size(bytes) } : Json).stringify()
  } catch {
    error => search_error(error.to_string())
  }
}
