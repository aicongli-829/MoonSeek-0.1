///|
fn feature_documents() -> Array[Json] {
  [
    {
      "id": "code",
      "root": "/workspace",
      "path": "src/search_engine.mbt",
      "name": "search_engine.mbt",
      "extension": "mbt",
      "size": "4096",
      "modified": "200",
      "content": "rank local documents with deterministic scoring",
    },
    {
      "id": "guide",
      "root": "/workspace",
      "path": "docs/quick-start.md",
      "name": "quick-start.md",
      "extension": "md",
      "size": "900",
      "modified": "100",
      "content": "MoonSeek quick start guide for local search",
    },
    {
      "id": "photo",
      "root": "/pictures",
      "path": "Summer Holiday.JPG",
      "name": "Summer Holiday.JPG",
      "extension": "jpg",
      "size": "5000000",
      "modified": "300",
      "content": "",
    },
  ]
}

///|
fn feature_index() -> Json raise {
  @json.parse(
    build_search_index_json(
      ({ "created": "test", "documents": feature_documents().to_json() } : Json).stringify(),
    ),
  )
}

///|
test "file categories cover common desktop formats" {
  assert_eq(file_category("PDF"), "document")
  assert_eq(file_category("xlsx"), "spreadsheet")
  assert_eq(file_category("pptx"), "presentation")
  assert_eq(file_category("jpeg"), "image")
  assert_eq(file_category("flac"), "audio")
  assert_eq(file_category("mkv"), "video")
  assert_eq(file_category("7z"), "archive")
  assert_eq(file_category("mbt"), "code")
  assert_eq(file_category("html"), "web")
  assert_eq(file_category("toml"), "data")
  assert_eq(file_category("ps1"), "script")
  assert_eq(file_category("exe"), "executable")
  assert_eq(file_category("woff2"), "font")
  assert_eq(file_category("unknown"), "other")
}

///|
test "category aliases are normalized in queries" {
  let query = parse_search_query("type:photos,docs kind:source")
  assert_eq(query.categories, ["image", "document", "code"])
}

///|
test "byte parser supports decimal and binary units" {
  assert_eq(parse_byte_count("1 KB"), Some(1000L))
  assert_eq(parse_byte_count("1KiB"), Some(1024L))
  assert_eq(parse_byte_count("1.5mb"), Some(1500000L))
  assert_eq(parse_byte_count("0"), Some(0L))
  assert_eq(parse_byte_count("broken"), None)
}

///|
test "named and comparison size ranges match boundaries" {
  let small = parse_size_range("small").unwrap()
  assert_true(number_in_range(1024L, small))
  assert_true(number_in_range(1024L * 1024L, small))
  assert_false(number_in_range(2L * 1024L * 1024L, small))
  let greater = parse_size_range(">10kb").unwrap()
  assert_false(number_in_range(10000L, greater))
  assert_true(number_in_range(10001L, greater))
  let interval = parse_size_range("1kb..2kb").unwrap()
  assert_true(number_in_range(1500L, interval))
  assert_false(number_in_range(2500L, interval))
}

///|
test "fuzzy filename scoring favors exact and prefix matches" {
  let exact = fuzzy_filename_score("moonseek", "MoonSeek")
  let prefix = fuzzy_filename_score("moon", "moonseek.exe")
  let subsequence = fuzzy_filename_score("mnsearch", "moon-search.mbt")
  assert_true(exact > prefix)
  assert_true(prefix > subsequence)
  assert_true(subsequence > 0.0)
}

///|
test "fuzzy filename scoring tolerates a short typo" {
  assert_true(fuzzy_filename_score("readne", "readme") > 0.0)
  assert_eq(fuzzy_filename_score("zzzz", "readme"), 0.0)
}

///|
test "search finds a metadata-only image by fuzzy filename" {
  let result = @json.parse(
    search_index_json(
      (
        { "index": feature_index(), "query": "summer holiday", "limit": 10 } :
        Json).stringify(),
    ),
  )
  let rows = search_array(result, "results")
  assert_eq(rows.length(), 1)
  assert_eq(search_text(rows[0], "id", ""), "photo")
}

///|
test "search combines file category and size filters" {
  let result = @json.parse(
    search_index_json(
      (
        {
          "index": feature_index(),
          "query": "type:image size:>1mb",
          "limit": 10,
        } : Json).stringify(),
    ),
  )
  let rows = search_array(result, "results")
  assert_eq(rows.length(), 1)
  assert_eq(search_text(rows[0], "category", ""), "image")
}

///|
test "search applies modified numeric ranges" {
  let result = @json.parse(
    search_index_json(
      (
        { "index": feature_index(), "query": "modified:150..250", "limit": 10 } :
        Json).stringify(),
    ),
  )
  let rows = search_array(result, "results")
  assert_eq(rows.length(), 1)
  assert_eq(search_text(rows[0], "id", ""), "code")
}

///|
test "suggestions combine files terms and filters" {
  let result = @json.parse(
    suggest_search_json(
      ({ "index": feature_index(), "prefix": "sea", "limit": 20 } : Json).stringify(),
    ),
  )
  let suggestions = search_array(result, "suggestions")
  assert_true(suggestions.length() >= 2)
  assert_true(suggestions.any(item => search_text(item, "kind", "") == "file"))
  assert_true(suggestions.any(item => search_text(item, "kind", "") == "term"))
}

///|
test "suggestions expose category filters" {
  let result = @json.parse(
    suggest_search_json(
      ({ "index": feature_index(), "prefix": "image", "limit": 20 } : Json).stringify(),
    ),
  )
  let suggestions = search_array(result, "suggestions")
  assert_true(
    suggestions.any(item => search_text(item, "value", "") == "type:image"),
  )
}

///|
test "validator accepts a freshly built index" {
  let report = @json.parse(
    validate_search_index_json(feature_index().stringify()),
  )
  match search_field(report, "valid") {
    true => ()
    _ => fail("fresh index should be valid")
  }
  assert_eq(search_int(report, "errors", -1), 0)
  assert_eq(search_int(report, "documents", -1), 3)
}

///|
test "validator reports out-of-range postings" {
  let invalid : Json = {
    "formatVersion": 1,
    "documents": [],
    "terms": [
      {
        "term": "broken",
        "documentFrequency": 1,
        "postings": [{ "document": 3, "content": 1, "name": 0, "path": 0 }],
      },
    ],
    "statistics": { "documents": 0, "terms": 1, "tokens": 0 },
  }
  let report = @json.parse(validate_search_index_json(invalid.stringify()))
  match search_field(report, "valid") {
    false => ()
    _ => fail("invalid posting should be rejected")
  }
  assert_true(search_int(report, "errors", 0) > 0)
}

///|
test "query parser keeps quoted phrase and negative term" {
  let query = parse_search_query("\"quick start\" -draft root:work")
  assert_eq(query.phrases, ["quick start"])
  assert_eq(query.excluded, ["draft"])
  assert_eq(query.root_filter, "work")
}

///|
test "facets count extensions categories roots and sizes" {
  let result = @json.parse(
    search_index_json(
      ({ "index": feature_index(), "query": "size:>=0", "limit": 10 } : Json).stringify(),
    ),
  )
  let facets = search_field(result, "facets")
  assert_eq(search_array(facets, "extensions").length(), 3)
  assert_eq(search_array(facets, "categories").length(), 3)
  assert_eq(search_array(facets, "roots").length(), 2)
  assert_true(search_array(facets, "sizes").length() >= 2)
}

///|
test "file size formatter chooses readable binary units" {
  assert_eq(format_file_size(0L), "0 bytes")
  assert_eq(format_file_size(1L), "1 byte")
  assert_eq(format_file_size(1024L), "1 KiB")
  assert_eq(format_file_size(1536L), "1.5 KiB")
  assert_eq(format_file_size(1024L * 1024L), "1 MiB")
  assert_eq(format_file_size(1024L * 1024L * 1024L), "1 GiB")
}

///|
test "search results explain match kind and formatted size" {
  let result = @json.parse(
    search_index_json(
      ({ "index": feature_index(), "query": "quick", "limit": 10 } : Json).stringify(),
    ),
  )
  let rows = search_array(result, "results")
  assert_eq(rows.length(), 1)
  assert_eq(search_text(rows[0], "matchKind", ""), "filename")
  assert_eq(search_text(rows[0], "sizeLabel", ""), "900 bytes")
}

///|
test "query help stays aligned with all filter families" {
  let help = @json.parse(search_query_help_json())
  let operators = search_array(help, "operators")
  assert_true(operators.length() >= 9)
  assert_true(
    operators.any(item => search_text(item, "syntax", "") == "type:category"),
  )
  assert_true(
    operators.any(item => search_text(item, "syntax", "") == "size:range"),
  )
}

///|
test "negative terms remove otherwise matching documents" {
  let result = @json.parse(
    search_index_json(
      (
        { "index": feature_index(), "query": "search -guide", "limit": 10 } :
        Json).stringify(),
    ),
  )
  let rows = search_array(result, "results")
  assert_eq(rows.length(), 1)
  assert_eq(search_text(rows[0], "id", ""), "code")
}

///|
test "an extension-only query returns all matching files" {
  let result = @json.parse(
    search_index_json(
      ({ "index": feature_index(), "query": "ext:md", "limit": 10 } : Json).stringify(),
    ),
  )
  let rows = search_array(result, "results")
  assert_eq(rows.length(), 1)
  assert_eq(search_text(rows[0], "id", ""), "guide")
}

///|
test "empty query reports a useful boundary error" {
  let result = @json.parse(
    search_index_json(
      ({ "index": feature_index(), "query": "", "limit": 10 } : Json).stringify(),
    ),
  )
  assert_true(search_text(result, "error", "").contains("filename"))
}

///|
test "validator detects duplicate document identities" {
  let duplicate : Json = {
    "formatVersion": 1,
    "documents": [
      { "id": "same", "path": "one.txt", "size": "1", "tokenCount": 0 },
      { "id": "same", "path": "two.txt", "size": "1", "tokenCount": 0 },
    ],
    "terms": [],
    "statistics": { "documents": 2, "terms": 0, "tokens": 0 },
  }
  let report = @json.parse(validate_search_index_json(duplicate.stringify()))
  assert_true(search_int(report, "errors", 0) > 0)
}

///|
test "suggestion limit is enforced after ranking" {
  let result = @json.parse(
    suggest_search_json(
      ({ "index": feature_index(), "prefix": "", "limit": 2 } : Json).stringify(),
    ),
  )
  assert_eq(search_array(result, "suggestions").length(), 2)
}
