///|
priv struct RankedDocument {
  document : Int
  mut score : Double
  matched : Array[String]
}

///|
fn term_rows(index : Json) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for row in search_array(index, "terms") {
    let term = search_text(row, "term", "")
    if term != "" {
      result[term] = row
    }
  }
  result
}

///|
fn document_matches_filters(document : Json, query : SearchQuery) -> Bool {
  let extension = search_text(document, "extension", "").to_lower()
  let path = search_text(document, "path", "").to_lower()
  let root = search_text(document, "root", "").to_lower()
  let size = search_int64(document, "size", 0L)
  let modified = search_int64(document, "modified", 0L)
  (query.extensions.length() == 0 || query.extensions.contains(extension)) &&
  category_matches(extension, query.categories) &&
  (query.path_filter == "" || path.contains(query.path_filter)) &&
  (query.root_filter == "" || root.contains(query.root_filter)) &&
  number_in_range(size, query.size) &&
  number_in_range(modified, query.modified)
}

///|
fn posting_weight(posting : Json) -> Double {
  search_int(posting, "content", 0).to_double() +
  search_int(posting, "name", 0).to_double() * 4.0 +
  search_int(posting, "path", 0).to_double() * 1.8
}

///|
fn contains_any_excluded(
  document_index : Int,
  excluded : Array[String],
  rows : Map[String, Json],
) -> Bool {
  for term in excluded {
    match rows.get(term) {
      Some(row) =>
        if search_array(row, "postings").any(posting => {
            search_int(posting, "document", -1) == document_index
          }) {
          return true
        }
      None => ()
    }
  }
  false
}

///|
fn phrase_bonus(
  document : Json,
  phrases : Array[String],
  raw_query : String,
) -> Double {
  let searchable = (search_text(document, "name", "") +
  " " +
  search_text(document, "path", "") +
  " " +
  search_text(document, "excerpt", "")).to_lower()
  let mut bonus = 0.0
  for phrase in phrases {
    if searchable.contains(phrase) {
      bonus = bonus + 6.0
    }
  }
  let clean_query = raw_query.trim().to_lower()
  if clean_query != "" &&
    !clean_query.contains(":") &&
    searchable.contains(clean_query) {
    bonus = bonus + 8.0
  }
  bonus
}

///|
fn snippet_for(document : Json, terms : Array[String]) -> String {
  let excerpt = search_text(document, "excerpt", "")
  let lower = excerpt.to_lower()
  let mut earliest : Int? = None
  for term in terms {
    match lower.find(term) {
      Some(index) =>
        match earliest {
          Some(current) if current <= index => ()
          _ => earliest = Some(index)
        }
      None => ()
    }
  }
  match earliest {
    Some(index) => {
      let start = (index - 80).max(0)
      let end = (start + 260).min(excerpt.length())
      (if start > 0 { "…" } else { "" }) +
      excerpt[start:end].to_owned() +
      (if end < excerpt.length() { "…" } else { "" })
    }
    None => excerpt
  }
}

///|
fn ranked_result_json(
  ranked : RankedDocument,
  document : Json,
  terms : Array[String],
) -> Json {
  {
    "id": search_text(document, "id", ""),
    "root": search_text(document, "root", ""),
    "path": search_text(document, "path", ""),
    "name": search_text(document, "name", ""),
    "extension": search_text(document, "extension", ""),
    "category": search_text(document, "category", "other"),
    "size": search_text(document, "size", "0"),
    "sizeLabel": format_file_size(search_int64(document, "size", 0L)),
    "modified": search_text(document, "modified", "0"),
    "score": ranked.score.to_string(),
    "matchedTerms": ranked.matched.to_json(),
    "matchKind": file_match_kind(ranked, document),
    "snippet": snippet_for(document, terms),
  }
}

///|
/// Search a persisted MoonSeek index using BM25-style length normalization and
/// explicit filename/path boosts. Results are deterministic for equal scores.
pub fn search_index_json(source : String) -> String {
  try {
    let request = search_parse(source, "search request")
    let index = search_field(request, "index")
    let raw_query = search_text(request, "query", "")
    let query = parse_search_query(raw_query)
    guard query.terms.length() > 0 ||
      query.extensions.length() > 0 ||
      query.categories.length() > 0 ||
      query.path_filter != "" ||
      query.root_filter != "" ||
      query.size.minimum is Some(_) ||
      query.size.maximum is Some(_) ||
      query.modified.minimum is Some(_) ||
      query.modified.maximum is Some(_) else {
      fail("enter a filename or content keyword")
    }
    let documents = search_array(index, "documents")
    let rows = term_rows(index)
    let scores : Map[Int, RankedDocument] = Map([])
    let document_count = documents.length().max(1)
    let statistics = search_field(index, "statistics")
    let average_length = match
      search_field(statistics, "averageDocumentTokens") {
      String(value) => (@string.parse_double(value) catch { _ => 1.0 }).max(1.0)
      _ => 1.0
    }
    for term in query.terms {
      match rows.get(term) {
        None => ()
        Some(row) => {
          let frequency = search_int(row, "documentFrequency", 0).max(1)
          let idf = @math.ln(
            (document_count.to_double() - frequency.to_double() + 0.5) /
            (frequency.to_double() + 0.5) +
            1.0,
          )
          for posting in search_array(row, "postings") {
            let document_index = search_int(posting, "document", -1)
            guard document_index >= 0 && document_index < documents.length() else {
              continue
            }
            let document = documents[document_index]
            if !document_matches_filters(document, query) ||
              contains_any_excluded(document_index, query.excluded, rows) {
              continue
            }
            let weighted_tf = posting_weight(posting)
            let length = search_int(document, "tokenCount", 0).to_double()
            let normalized = weighted_tf *
              2.2 /
              (weighted_tf + 1.2 * (0.25 + 0.75 * length / average_length))
            let ranked = scores
              .get(document_index)
              .unwrap_or_else(() => {
                let created = {
                  document: document_index,
                  score: 0.0,
                  matched: [],
                }
                scores[document_index] = created
                created
              })
            ranked.score = ranked.score + idf * normalized
            if !ranked.matched.contains(term) {
              ranked.matched.push(term)
            }
          }
        }
      }
    }
    if query.terms.length() == 0 {
      for document_index, document in documents {
        if document_matches_filters(document, query) &&
          !contains_any_excluded(document_index, query.excluded, rows) {
          scores[document_index] = {
            document: document_index,
            score: 1.0,
            matched: [],
          }
        }
      }
    }
    let fuzzy_source = query.terms.join(" ")
    if fuzzy_source != "" {
      for document_index, document in documents {
        if document_matches_filters(document, query) &&
          !contains_any_excluded(document_index, query.excluded, rows) {
          let fuzzy = fuzzy_filename_score(
            fuzzy_source,
            search_text(document, "name", ""),
          )
          if fuzzy > 0.0 {
            let ranked = scores
              .get(document_index)
              .unwrap_or_else(() => {
                let created = {
                  document: document_index,
                  score: 0.0,
                  matched: [],
                }
                scores[document_index] = created
                created
              })
            ranked.score = ranked.score + fuzzy
          }
        }
      }
    }
    let ranked = scores.values().collect()
    for item in ranked {
      item.score = item.score +
        phrase_bonus(documents[item.document], query.phrases, raw_query)
    }
    ranked.sort_by((left, right) => {
      if left.score > right.score {
        -1
      } else if left.score < right.score {
        1
      } else {
        search_text(documents[left.document], "path", "").compare(
          search_text(documents[right.document], "path", ""),
        )
      }
    })
    let limit = search_int(request, "limit", 50).clamp(min=1, max=200)
    let results : Array[Json] = []
    for index, item in ranked {
      if index >= limit {
        break
      }
      results.push(
        ranked_result_json(item, documents[item.document], query.terms),
      )
    }
    (
      {
        "query": query_to_json(query),
        "rawQuery": raw_query,
        "total": ranked.length(),
        "facets": search_facets(ranked.map(item => item.document), documents),
        "results": results.to_json(),
      } : Json).stringify()
  } catch {
    error => search_error(error.to_string())
  }
}
