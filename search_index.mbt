///|
priv struct TermCounts {
  mut content : Int
  mut name : Int
  mut path : Int
}

///|
priv struct IndexedSearchDocument {
  id : String
  root : String
  path : String
  name : String
  extension : String
  category : String
  size : Int64
  modified : Int64
  token_count : Int
  excerpt : String
  term_counts : Array[Json]
}

///|
fn count_tokens(source : String) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  for token in search_tokens(source) {
    counts[token] = counts.get(token).unwrap_or(0) + 1
  }
  counts
}

///|
fn add_term_counts(
  aggregate : Map[String, TermCounts],
  values : Map[String, Int],
  field : String,
) -> Unit {
  for term, count in values {
    let item = aggregate
      .get(term)
      .unwrap_or_else(() => {
        let created = { content: 0, name: 0, path: 0, }
        aggregate[term] = created
        created
      })
    match field {
      "name" => item.name = item.name + count
      "path" => item.path = item.path + count
      _ => item.content = item.content + count
    }
  }
}

///|
fn excerpt_of(content : String) -> String {
  let normalized = content
    .replace_all(old="\r", new=" ")
    .replace_all(old="\n", new=" ")
    .replace_all(old="\t", new=" ")
  if normalized.length() <= 360 {
    normalized
  } else {
    normalized[:360].to_owned() + "…"
  }
}

///|
fn index_document_json(document : IndexedSearchDocument) -> Json {
  {
    "id": document.id,
    "root": document.root,
    "path": document.path,
    "name": document.name,
    "extension": document.extension,
    "category": document.category,
    "size": document.size.to_string(),
    "modified": document.modified.to_string(),
    "tokenCount": document.token_count,
    "excerpt": document.excerpt,
    "termCounts": document.term_counts.to_json(),
  }
}

///|
fn posting_json(document : Int, counts : TermCounts) -> Json {
  {
    "document": document,
    "content": counts.content,
    "name": counts.name,
    "path": counts.path,
  }
}

///|
/// Build a deterministic inverted index from already decoded text documents.
/// Native adapters own filesystem access; this pure layer owns tokenization and
/// the persisted index format.
pub fn build_search_index_json(source : String) -> String {
  try {
    let request = search_parse(source, "index request")
    let raw_documents = search_array(request, "documents")
    let documents : Array[IndexedSearchDocument] = []
    let postings : Map[String, Array[Json]] = Map([])
    let mut total_tokens = 0
    for raw in raw_documents {
      let id = search_text(raw, "id", "")
      let path = search_text(raw, "path", "")
      let name = search_text(raw, "name", path)
      let content = search_text(raw, "content", "")
      guard id != "" && path != "" else {
        fail("every indexed document requires id and path")
      }
      let term_counts : Map[String, TermCounts] = Map([])
      let cached_terms = search_array(raw, "termCounts")
      let mut content_token_count = search_int(raw, "tokenCount", 0)
      if cached_terms.length() > 0 {
        for cached in cached_terms {
          let term = search_text(cached, "term", "")
          if term != "" {
            term_counts[term] = {
              content: search_int(cached, "content", 0),
              name: search_int(cached, "name", 0),
              path: search_int(cached, "path", 0),
            }
          }
        }
      } else {
        let content_counts = count_tokens(content)
        content_token_count = 0
        for _, count in content_counts {
          content_token_count = content_token_count + count
        }
        add_term_counts(term_counts, content_counts, "content")
        add_term_counts(term_counts, count_tokens(name), "name")
        add_term_counts(term_counts, count_tokens(path), "path")
      }
      let serialized_terms : Array[Json] = []
      let serialized_keys = term_counts.keys().collect()
      serialized_keys.sort()
      for term in serialized_keys {
        let counts = term_counts.get(term).unwrap()
        serialized_terms.push({
          "term": term,
          "content": counts.content,
          "name": counts.name,
          "path": counts.path,
        })
      }
      let document_index = documents.length()
      let indexed = {
        id,
        root: search_text(raw, "root", ""),
        path,
        name,
        extension: clean_extension(search_text(raw, "extension", "")),
        category: file_category(search_text(raw, "extension", "")),
        size: search_int64(raw, "size", 0L),
        modified: search_int64(raw, "modified", 0L),
        token_count: content_token_count,
        excerpt: if content == "" {
          search_text(raw, "excerpt", "")
        } else {
          excerpt_of(content)
        },
        term_counts: serialized_terms,
      }
      documents.push(indexed)
      total_tokens = total_tokens + content_token_count
      for term, counts in term_counts {
        match postings.get(term) {
          Some(items) => items.push(posting_json(document_index, counts))
          None => postings[term] = [posting_json(document_index, counts)]
        }
      }
    }
    let terms = postings.keys().collect()
    terms.sort()
    let term_rows : Array[Json] = []
    for term in terms {
      let items = postings.get(term).unwrap_or([])
      term_rows.push({
        "term": term,
        "documentFrequency": items.length(),
        "postings": items.to_json(),
      })
    }
    (
      {
        "formatVersion": 1,
        "created": search_text(request, "created", ""),
        "documents": documents.map(index_document_json).to_json(),
        "terms": term_rows.to_json(),
        "statistics": {
          "documents": documents.length(),
          "terms": terms.length(),
          "tokens": total_tokens,
          "averageDocumentTokens": if documents.length() == 0 {
            "0"
          } else {
            (total_tokens.to_double() / documents.length().to_double()).to_string()
          },
        },
      } : Json).stringify()
  } catch {
    error => search_error(error.to_string())
  }
}
