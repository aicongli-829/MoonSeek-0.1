///|
priv struct SearchSuggestion {
  value : String
  kind : String
  mut score : Double
  detail : String
}

///|
fn suggestion_json(item : SearchSuggestion) -> Json {
  {
    "value": item.value,
    "kind": item.kind,
    "score": item.score.to_string(),
    "detail": item.detail,
  }
}

///|
fn put_suggestion(
  suggestions : Map[String, SearchSuggestion],
  value : String,
  kind : String,
  score : Double,
  detail : String,
) -> Unit {
  let key = kind + ":" + value
  match suggestions.get(key) {
    Some(existing) => existing.score = existing.score.max(score)
    None => suggestions[key] = { value, kind, score, detail, }
  }
}

///|
fn suggest_terms(
  index : Json,
  prefix : String,
  suggestions : Map[String, SearchSuggestion],
) -> Unit {
  for row in search_array(index, "terms") {
    let term = search_text(row, "term", "")
    if term.length() >= 2 && (prefix == "" || term.has_prefix(prefix)) {
      let frequency = search_int(row, "documentFrequency", 0)
      put_suggestion(
        suggestions,
        term,
        "term",
        2.0 + frequency.to_double(),
        frequency.to_string() + " files",
      )
    }
  }
}

///|
fn suggest_files(
  index : Json,
  prefix : String,
  suggestions : Map[String, SearchSuggestion],
) -> Unit {
  for document in search_array(index, "documents") {
    let name = search_text(document, "name", "")
    let score = if prefix == "" {
      0.0
    } else {
      fuzzy_filename_score(prefix, name)
    }
    if score > 0.0 {
      put_suggestion(
        suggestions,
        name,
        "file",
        20.0 + score,
        search_text(document, "path", ""),
      )
    }
  }
}

///|
fn suggest_filters(
  index : Json,
  prefix : String,
  suggestions : Map[String, SearchSuggestion],
) -> Unit {
  let extensions : Map[String, Int] = Map([])
  let categories : Map[String, Int] = Map([])
  for document in search_array(index, "documents") {
    let extension = search_text(document, "extension", "")
    let category = search_text(document, "category", file_category(extension))
    if extension != "" {
      extensions[extension] = extensions.get(extension).unwrap_or(0) + 1
    }
    categories[category] = categories.get(category).unwrap_or(0) + 1
  }
  for extension, count in extensions {
    let value = "ext:" + extension
    if prefix == "" || value.has_prefix(prefix) || extension.has_prefix(prefix) {
      put_suggestion(
        suggestions,
        value,
        "filter",
        10.0 + count.to_double(),
        count.to_string() + " files",
      )
    }
  }
  for category, count in categories {
    let value = "type:" + category
    if prefix == "" || value.has_prefix(prefix) || category.has_prefix(prefix) {
      put_suggestion(
        suggestions,
        value,
        "filter",
        10.0 + count.to_double(),
        count.to_string() + " files",
      )
    }
  }
}

///|
pub fn suggest_search_json(source : String) -> String {
  try {
    let request = search_parse(source, "suggest request")
    let index = search_field(request, "index")
    let prefix = search_text(request, "prefix", "").trim().to_owned().to_lower()
    let limit = search_int(request, "limit", 12).clamp(min=1, max=50)
    let suggestions : Map[String, SearchSuggestion] = Map([])
    suggest_files(index, prefix, suggestions)
    suggest_filters(index, prefix, suggestions)
    if prefix.length() >= 2 {
      suggest_terms(index, prefix, suggestions)
    }
    let ranked = suggestions.values().collect()
    ranked.sort_by((left, right) => {
      if left.score > right.score {
        -1
      } else if left.score < right.score {
        1
      } else {
        left.value.compare(right.value)
      }
    })
    let result : Array[Json] = []
    for position, item in ranked {
      if position >= limit {
        break
      }
      result.push(suggestion_json(item))
    }
    ({ "prefix": prefix, "suggestions": result.to_json() } : Json).stringify()
  } catch {
    error => search_error(error.to_string())
  }
}
