///|
test "mixed tokenizer keeps English words and CJK search units" {
  assert_eq(search_tokens("MoonBit 快捷搜索 2026"), [
    "moonbit", "快", "快捷", "捷", "捷搜", "搜", "搜索", "索", "2026",
  ])
}

///|
test "query parser extracts filters and exclusions" {
  let query = parse_search_query("MoonBit ext:md,mbt path:docs -draft")
  assert_eq(query.terms, ["moonbit"])
  assert_eq(query.extensions, ["md", "mbt"])
  assert_eq(query.path_filter, "docs")
  assert_eq(query.excluded, ["draft"])
}

///|
test "index ranks filename matches above content-only matches" {
  let index = build_search_index_json(
    (
      {
        "created": "test",
        "documents": [
          {
            "id": "1",
            "root": "/notes",
            "path": "docs/moonbit-guide.md",
            "name": "moonbit-guide.md",
            "extension": "md",
            "size": "100",
            "modified": "1",
            "content": "language notes",
          },
          {
            "id": "2",
            "root": "/notes",
            "path": "docs/languages.md",
            "name": "languages.md",
            "extension": "md",
            "size": "200",
            "modified": "2",
            "content": "MoonBit language reference",
          },
        ],
      } : Json).stringify(),
  )
  let result = search_index_json(
    ({ "index": @json.parse(index), "query": "moonbit", "limit": 10 } : Json).stringify(),
  )
  let parsed = @json.parse(result)
  let rows = search_array(parsed, "results")
  inspect(rows.length(), content="2")
  assert_eq(search_text(rows[0], "id", ""), "1")
}
