///|
test "segment wildcard supports stars and question marks" {
  assert_true(wildcard_segment("*.log", "server.log"))
  assert_true(wildcard_segment("file-??.txt", "file-01.txt"))
  assert_false(wildcard_segment("*.md", "readme.txt"))
}

///|
test "path wildcard supports recursive double star" {
  assert_true(
    wildcard_path("docs/**/generated/*.md", "docs/api/generated/a.md"),
  )
  assert_true(wildcard_path("docs/**/generated/*.md", "docs/generated/a.md"))
  assert_false(wildcard_path("docs/**/generated/*.md", "src/generated/a.md"))
}

///|
test "ignore parser skips comments and records flags" {
  let rules = parse_search_ignore(
    "# generated files\n/build/\n*.log\n!important.log\n",
  )
  assert_eq(rules.length(), 3)
  assert_true(rules[0].anchored)
  assert_true(rules[0].directory_only)
  assert_true(rules[2].negative)
}

///|
test "later negative rule restores a matching file" {
  let rules = parse_search_ignore("*.log\n!important.log\n")
  assert_true(search_path_ignored("logs/debug.log", false, rules))
  assert_false(search_path_ignored("logs/important.log", false, rules))
}

///|
test "directory-only rule does not hide a same-named file" {
  let rules = parse_search_ignore("cache/\n")
  assert_true(search_path_ignored("cache", true, rules))
  assert_false(search_path_ignored("cache", false, rules))
}

///|
test "CLI joins query words while removing option pairs" {
  let args = [
    "moonseek", "search", "error", "code", "ext:log", "--limit", "20", "--database",
    "state.json", "-debug",
  ]
  assert_eq(search_query_from_arguments(args, 2), "error code ext:log -debug")
}
