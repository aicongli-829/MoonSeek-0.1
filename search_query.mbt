///|
priv struct SearchQuery {
  terms : Array[String]
  excluded : Array[String]
  phrases : Array[String]
  extensions : Array[String]
  categories : Array[String]
  path_filter : String
  root_filter : String
  size : NumberRange
  modified : NumberRange
}

///|
fn query_pieces(source : String) -> Array[String] {
  let pieces : Array[String] = []
  let mut current = StringBuilder()
  let mut quoted = false
  for char in source.trim() {
    if char == '"' {
      quoted = !quoted
      if !quoted && current.to_string() != "" {
        pieces.push("\"" + current.to_string() + "\"")
        current = StringBuilder()
      }
    } else if char.is_whitespace() && !quoted {
      if current.to_string() != "" {
        pieces.push(current.to_string())
        current = StringBuilder()
      }
    } else {
      current.write_char(char)
    }
  }
  if current.to_string() != "" {
    pieces.push(current.to_string())
  }
  pieces
}

///|
fn clean_extension(value : String) -> String {
  value.trim().trim_start(chars=['.']).to_owned().to_lower()
}

///|
fn parse_search_query(source : String) -> SearchQuery {
  let terms : Array[String] = []
  let excluded : Array[String] = []
  let phrases : Array[String] = []
  let extensions : Array[String] = []
  let categories : Array[String] = []
  let mut path_filter = ""
  let mut root_filter = ""
  let mut size = empty_number_range()
  let mut modified = empty_number_range()
  for piece in query_pieces(source) {
    let lower = piece.to_lower()
    if lower.has_prefix("ext:") {
      for item in lower[4:].split(",") {
        let extension = clean_extension(item.to_owned())
        if extension != "" && !extensions.contains(extension) {
          extensions.push(extension)
        }
      }
    } else if lower.has_prefix("type:") || lower.has_prefix("kind:") {
      let offset = if lower.has_prefix("type:") { 5 } else { 5 }
      for item in lower[offset:].split(",") {
        let category = canonical_file_category(item.to_owned())
        if category != "" && !categories.contains(category) {
          categories.push(category)
        }
      }
    } else if lower.has_prefix("path:") {
      path_filter = lower[5:].trim(chars=['"']).to_owned()
    } else if lower.has_prefix("root:") {
      root_filter = lower[5:].trim(chars=['"']).to_owned()
    } else if lower.has_prefix("size:") {
      match parse_size_range(lower[5:].to_owned()) {
        Some(range) => size = range
        None => ()
      }
    } else if lower.has_prefix("modified:") {
      match parse_size_range(lower[9:].to_owned()) {
        Some(range) => modified = range
        None => ()
      }
    } else if lower.length() >= 2 && lower.has_prefix("-") {
      excluded.push_iter(unique_search_tokens(lower[1:].to_owned()).iter())
    } else if lower.length() >= 2 &&
      lower.has_prefix("\"") &&
      lower.has_suffix("\"") {
      let phrase = lower[1:lower.length() - 1].to_owned()
      if phrase != "" {
        phrases.push(phrase)
        terms.push_iter(unique_search_tokens(phrase).iter())
      }
    } else if lower != "and" && lower != "or" {
      terms.push_iter(unique_search_tokens(lower).iter())
    }
  }
  {
    terms,
    excluded,
    phrases,
    extensions,
    categories,
    path_filter,
    root_filter,
    size,
    modified,
  }
}

///|
fn query_to_json(query : SearchQuery) -> Json {
  {
    "terms": query.terms.to_json(),
    "excluded": query.excluded.to_json(),
    "phrases": query.phrases.to_json(),
    "extensions": query.extensions.to_json(),
    "categories": query.categories.to_json(),
    "path": query.path_filter,
    "root": query.root_filter,
    "size": range_to_json(query.size),
    "modified": range_to_json(query.modified),
  }
}
