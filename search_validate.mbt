///|
priv struct IndexDiagnostic {
  level : String
  code : String
  message : String
  location : String
}

///|
fn diagnostic_json(item : IndexDiagnostic) -> Json {
  {
    "level": item.level,
    "code": item.code,
    "message": item.message,
    "location": item.location,
  }
}

///|
fn add_diagnostic(
  diagnostics : Array[IndexDiagnostic],
  level : String,
  code : String,
  message : String,
  location : String,
) -> Unit {
  diagnostics.push({ level, code, message, location, })
}

///|
fn validate_index_documents(
  index : Json,
  diagnostics : Array[IndexDiagnostic],
) -> Map[String, Int] {
  let ids : Map[String, Int] = Map([])
  let documents = search_array(index, "documents")
  for position, document in documents {
    let location = "documents[" + position.to_string() + "]"
    let id = search_text(document, "id", "")
    let path = search_text(document, "path", "")
    let extension = search_text(document, "extension", "")
    if id == "" {
      add_diagnostic(
        diagnostics, "error", "document.id.empty", "Document id is empty.", location,
      )
    } else {
      match ids.get(id) {
        Some(first) =>
          add_diagnostic(
            diagnostics,
            "error",
            "document.id.duplicate",
            "Document id duplicates position " + first.to_string() + ".",
            location,
          )
        None => ids[id] = position
      }
    }
    if path == "" {
      add_diagnostic(
        diagnostics, "error", "document.path.empty", "Document path is empty.", location,
      )
    }
    if search_int(document, "tokenCount", -1) < 0 {
      add_diagnostic(
        diagnostics, "error", "document.tokens.invalid", "Token count must be zero or greater.",
        location,
      )
    }
    if search_int64(document, "size", -1L) < 0L {
      add_diagnostic(
        diagnostics, "error", "document.size.invalid", "File size is invalid.", location,
      )
    }
    let stored_category = search_text(document, "category", "")
    let expected_category = file_category(extension)
    if stored_category != "" && stored_category != expected_category {
      add_diagnostic(
        diagnostics, "warning", "document.category.stale", "Stored category does not match the file extension.",
        location,
      )
    }
  }
  ids
}

///|
fn validate_posting(
  posting : Json,
  term : String,
  position : Int,
  document_count : Int,
  diagnostics : Array[IndexDiagnostic],
) -> Int? {
  let location = "terms[" + term + "].postings[" + position.to_string() + "]"
  let document = search_int(posting, "document", -1)
  if document < 0 || document >= document_count {
    add_diagnostic(
      diagnostics, "error", "posting.document.invalid", "Posting points outside the document table.",
      location,
    )
    return None
  }
  let content = search_int(posting, "content", -1)
  let name = search_int(posting, "name", -1)
  let path = search_int(posting, "path", -1)
  if content < 0 || name < 0 || path < 0 || content + name + path == 0 {
    add_diagnostic(
      diagnostics, "error", "posting.count.invalid", "Posting counts must be nonnegative and contain at least one hit.",
      location,
    )
  }
  Some(document)
}

///|
fn validate_index_terms(
  index : Json,
  diagnostics : Array[IndexDiagnostic],
) -> Int {
  let terms = search_array(index, "terms")
  let document_count = search_array(index, "documents").length()
  let seen : Map[String, Bool] = Map([])
  let mut previous_term = ""
  let mut posting_count = 0
  for position, row in terms {
    let term = search_text(row, "term", "")
    let location = "terms[" + position.to_string() + "]"
    if term == "" {
      add_diagnostic(
        diagnostics, "error", "term.empty", "Term is empty.", location,
      )
    }
    if seen.contains(term) {
      add_diagnostic(
        diagnostics, "error", "term.duplicate", "Term occurs more than once.", location,
      )
    }
    seen[term] = true
    if previous_term != "" && previous_term.compare(term) > 0 {
      add_diagnostic(
        diagnostics, "warning", "term.order", "Terms are not stored in deterministic order.",
        location,
      )
    }
    previous_term = term
    let postings = search_array(row, "postings")
    if search_int(row, "documentFrequency", -1) != postings.length() {
      add_diagnostic(
        diagnostics, "error", "term.frequency.mismatch", "Document frequency does not equal the posting count.",
        location,
      )
    }
    let posting_documents : Map[Int, Bool] = Map([])
    for posting_position, posting in postings {
      match
        validate_posting(
          posting, term, posting_position, document_count, diagnostics,
        ) {
        Some(document) => {
          if posting_documents.contains(document) {
            add_diagnostic(
              diagnostics, "error", "posting.duplicate", "A term has multiple postings for the same document.",
              location,
            )
          }
          posting_documents[document] = true
        }
        None => ()
      }
    }
    posting_count = posting_count + postings.length()
  }
  posting_count
}

///|
fn validate_index_statistics(
  index : Json,
  diagnostics : Array[IndexDiagnostic],
) -> Unit {
  let statistics = search_field(index, "statistics")
  let documents = search_array(index, "documents")
  let terms = search_array(index, "terms")
  if search_int(statistics, "documents", -1) != documents.length() {
    add_diagnostic(
      diagnostics, "warning", "statistics.documents", "Stored document total is stale.",
      "statistics",
    )
  }
  if search_int(statistics, "terms", -1) != terms.length() {
    add_diagnostic(
      diagnostics, "warning", "statistics.terms", "Stored term total is stale.",
      "statistics",
    )
  }
  let mut tokens = 0
  for document in documents {
    tokens = tokens + search_int(document, "tokenCount", 0)
  }
  if search_int(statistics, "tokens", -1) != tokens {
    add_diagnostic(
      diagnostics, "warning", "statistics.tokens", "Stored token total is stale.",
      "statistics",
    )
  }
}

///|
fn validate_search_index(index : Json) -> Json {
  let diagnostics : Array[IndexDiagnostic] = []
  if search_int(index, "formatVersion", -1) != 1 {
    add_diagnostic(
      diagnostics, "error", "format.unsupported", "Only index format version 1 is supported.",
      "formatVersion",
    )
  }
  let ids = validate_index_documents(index, diagnostics)
  let postings = validate_index_terms(index, diagnostics)
  validate_index_statistics(index, diagnostics)
  let errors = diagnostics.filter(item => item.level == "error").length()
  let warnings = diagnostics.filter(item => item.level == "warning").length()
  {
    "valid": errors == 0,
    "errors": errors,
    "warnings": warnings,
    "documents": ids.length(),
    "terms": search_array(index, "terms").length(),
    "postings": postings,
    "diagnostics": diagnostics.map(diagnostic_json).to_json(),
  }
}

///|
pub fn validate_search_index_json(source : String) -> String {
  validate_search_index(search_parse(source, "search index")).stringify() catch {
    error => search_error(error.to_string())
  }
}
