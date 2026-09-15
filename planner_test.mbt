///|
fn sample(path : String) -> FileEntry {
  {
    path,
    name: base_name(path),
    month: "2026-09",
    size: "10",
    hash: "sample",
  }
}

///|
fn rule(kind : String, value : String, replacement : String) -> RenameRule {
  { kind, value, replacement }
}

///|
test "natural ordering handles numbered lessons and large digit runs" {
  let names = ["第10讲.txt", "第2讲.txt", "第1讲.txt"]
  names.sort_by(natural_compare)
  assert_eq(names, ["第1讲.txt", "第2讲.txt", "第10讲.txt"])
  assert_true(natural_compare("x999999999999999999999", "x1000000000000000000000") < 0)
  assert_true(natural_compare("x2", "x02") < 0)
  assert_true(natural_compare("a", "a") == 0)
}

///|
test "natural comparison remains antisymmetric across case and zeros" {
  let values = ["", "A", "a", "A01", "a1", "a2", "a10", "中文2", "中文10", "000"]
  for a in values {
    for b in values {
      let ab = natural_compare(a, b)
      let ba = natural_compare(b, a)
      assert_true((ab == 0 && ba == 0) || (ab < 0 && ba > 0) || (ab > 0 && ba < 0))
    }
  }
}

///|
test "natural comparison is transitive for mixed filenames" {
  let values = ["a01", "A1", "a2", "a10", "a100", "a9x", "a9z", "b1"]
  for a in values {
    for b in values {
      for c in values {
        if natural_compare(a, b) < 0 && natural_compare(b, c) < 0 {
          assert_true(natural_compare(a, c) < 0)
        }
      }
    }
  }
}

///|
test "extensions preserve dotfiles and split compound names at final dot" {
  assert_eq(split_extension(".env"), (".env", ""))
  assert_eq(split_extension("backup.tar.gz"), ("backup.tar", ".gz"))
  assert_eq(split_extension("README"), ("README", ""))
  assert_eq(split_extension("照片.JPG"), ("照片", ".JPG"))
}

///|
test "portable filenames reject devices and path injection" {
  for name in ["CON", "nul.txt", "COM9.log", "LPT1.pdf", "bad?name", "x/y", "x\\y", "a.", "a ", "", ".."] {
    assert_true(filename_error(name) is Some(_))
  }
  for name in ["控制台.txt", "console.txt", "com10.txt", ".env", "第1讲.pdf"] {
    assert_eq(filename_error(name), None)
  }
  for path in ["../outside.txt", "/tmp/file", "C:/a", "safe/../bad", ".git/config", "a//b"] {
    assert_true(path_error(path) is Some(_))
  }
  assert_eq(path_error("课程/2026-09/第1讲.pdf"), None)
}

///|
test "rule ordering changes the result while preserving the extension" {
  let first = [rule("prefix", "A_", ""), rule("lower", "", "")]
  let second = [rule("lower", "", ""), rule("prefix", "A_", "")]
  assert_eq(rename_file("PHOTO.JPG", first, 1, 3), "a_photo.JPG")
  assert_eq(rename_file("PHOTO.JPG", second, 1, 3), "A_photo.JPG")
  assert_eq(rename_file("PHOTO.JPG", [rule("extension_lower", "", "")], 1, 3), "PHOTO.jpg")
}

///|
test "replace and remove do not alter extension text" {
  let rules = [rule("remove", " (副本)", ""), rule("replace", "旧", "新")]
  assert_eq(rename_file("旧资料 (副本).pdf", rules, 1, 3), "新资料.pdf")
  assert_eq(rename_file("pdf内容.pdf", [rule("replace", "pdf", "文档")], 1, 3), "文档内容.pdf")
}

///|
test "space normalization preserves word separation" {
  assert_eq(normalize_spaces("  hello\t world　 "), "hello world")
  assert_eq(normalize_spaces("　　"), "")
  assert_eq(normalize_spaces("中文 名称"), "中文 名称")
  let rules = [rule("separator", "_", "")]
  assert_eq(rename_file("  meeting   notes.txt", rules, 1, 3), "meeting_notes.txt")
}

///|
test "numbering supports replacement and suffix without truncation" {
  assert_eq(rename_file("原件.pdf", [rule("number", "合同_", "")], 7, 3), "合同_007.pdf")
  assert_eq(rename_file("原件.pdf", [rule("number_suffix", "_", "")], 1234, 3), "原件_1234.pdf")
  assert_eq(padded_number(0, 3), "000")
}

///|
test "regular expressions use literal replacement text" {
  assert_eq(rename_file("img123.png", [rule("regex", "[0-9]+", "X")], 1, 3), "imgX.png")
  assert_eq(rename_file("img123.png", [rule("regex", "[0-9]+", "$1")], 1, 3), "img$1.png")
  let options = { ..default_options(), rules: [rule("regex", "[", "")] }
  assert_true(validate_options(options).length() > 0)
}

///|
test "custom classification respects first-match priority" {
  let rules : Array[CategoryRule] = [
    { kind: "keyword", value: "合同", folder: "工作/合同" },
    { kind: "extension", value: "pdf, DOCX", folder: "文档" },
  ]
  assert_eq(custom_category("合同.PDF", rules), "工作/合同")
  assert_eq(custom_category("说明.DOCX", rules), "文档")
  assert_eq(custom_category("photo.png", rules), "其他")
}

///|
test "planner is deterministic and does not mutate inventory" {
  let files = [sample("第10讲.pdf"), sample("第2讲.pdf")]
  let original = files.copy()
  let options = { ..default_options(), rules: [rule("number", "课程_", "")] }
  let first = plan(files, files.map(f => f.path), options)
  let second = plan(files, files.map(f => f.path), options)
  assert_eq(first, second)
  assert_eq(files, original)
  assert_eq(first[0].source, "第2讲.pdf")
  assert_eq(first[0].target, "文档/课程_001.pdf")
  assert_eq(first[1].target, "文档/课程_002.pdf")
}

///|
test "unselected existing targets still prevent overwrites" {
  let files = [sample("notes.txt")]
  let result = plan(files, ["notes.txt", "文档/notes.txt"], default_options())
  assert_eq(result[0].status, "conflict")
}

///|
test "case-insensitive target collisions are detected portably" {
  let files = [sample("one.txt"), sample("ONE.TXT")]
  let options = { ..default_options(), rules: [rule("lower", "", ""), rule("extension_lower", "", "")] }
  let result = plan(files, files.map(f => f.path), options)
  assert_eq(result.filter(r => r.status == "ready").length(), 1)
  assert_eq(result.filter(r => r.status == "conflict").length(), 1)
}

///|
test "automatic conflict suffix respects occupied numbered names" {
  let options = { ..default_options(), conflict: "number" }
  let result = plan([sample("notes.txt")], ["notes.txt", "文档/notes.txt", "文档/notes (2).txt"], options)
  assert_eq(result[0].target, "文档/notes (3).txt")
  assert_eq(result[0].status, "ready")
}

///|
test "repeated classification is idempotent" {
  let file = sample("文档/notes.txt")
  let result = plan([file], [file.path], default_options())
  assert_eq(result[0].status, "unchanged")
  assert_eq(result[0].target, file.path)
}

///|
test "manual exclusion leaves numbering contiguous" {
  let options = {
    ..default_options(),
    excluded: ["a.txt"],
    rules: [rule("number", "", "")],
  }
  let result = plan([sample("a.txt"), sample("b.txt")], ["a.txt", "b.txt"], options)
  assert_eq(result[0].status, "excluded")
  assert_eq(result[1].target, "文档/001.txt")
}

///|
test "category path injection blocks affected rows" {
  let options = {
    ..default_options(),
    classify: "custom",
    categories: [{ kind: "extension", value: "txt", folder: "../outside" }],
  }
  assert_true(validate_options(options).length() > 0)
  let result = plan([sample("a.txt")], ["a.txt"], options)
  assert_eq(result[0].status, "invalid")
}

///|
test "rename injection cannot create new directory components" {
  let options = { ..default_options(), rules: [rule("prefix", "../", "")] }
  let result = plan([sample("a.txt")], ["a.txt"], options)
  assert_eq(result[0].status, "invalid")
}

///|
test "quarantine requires a keeper and uses original relative path" {
  let files = [sample("a.txt"), sample("old/a.txt")]
  let options = { ..default_options(), quarantine: ["old/a.txt"] }
  let result = plan(files, files.map(f => f.path), options)
  let isolated = result.filter(r => r.source == "old/a.txt")[0]
  assert_eq(isolated.target, "重复文件隔离/old/a.txt")
  assert_eq(isolated.status, "ready")
  let invalid = { ..options, quarantine: ["a.txt", "old/a.txt"] }
  assert_true(plan(files, files.map(f => f.path), invalid).all(r => r.status == "invalid"))
}

///|
test "empty inventory produces empty preview" {
  assert_eq(plan([], [], default_options()), [])
}

///|
test "invalid options are reported before planning" {
  let options = {
    ..default_options(),
    sequence_start: -1,
    sequence_width: 10,
    classify: "unknown",
    conflict: "overwrite",
    sort: "random",
  }
  assert_eq(validate_options(options).length(), 5)
}

///|
test "JSON boundary reports invalid JSON without side effects" {
  assert_true(plan_json("{broken").contains("error"))
  assert_true(plan_json("{\"options\":{\"classify\":\"bad\"}}").contains("未知分类方式"))
  let input = (
    #|{"files":[{"path":"a.txt","name":"a.txt","month":"2026-09","size":"1","hash":"x"}],"occupied":["a.txt"],"options":{"classify":"type"}}
  )
  assert_true(plan_json(input).contains("文档/a.txt"))
}

///|
test "same-basename files from different folders receive unique targets" {
  let files = [sample("one/a.txt"), sample("two/a.txt"), sample("three/a.txt")]
  let rows = plan(files, files.map(f => f.path), { ..default_options(), conflict: "number" })
  let targets : Map[String, Bool] = Map([])
  for row in rows {
    assert_eq(row.status, "ready")
    assert_true(!targets.contains(row.target.to_lower()))
    targets[row.target.to_lower()] = true
  }
}

///|
test "month sorting uses stable path tie-breakers" {
  let files = [
    { ..sample("c.txt"), month: "2026-10" },
    { ..sample("b.txt"), month: "2026-08" },
    { ..sample("a.txt"), month: "2026-08" },
  ]
  let options = { ..default_options(), classify: "month", sort: "month" }
  let result = plan(files, files.map(f => f.path), options)
  assert_eq(result.map(r => r.source), ["a.txt", "b.txt", "c.txt"])
  assert_eq(result[0].target, "2026-08/a.txt")
}
