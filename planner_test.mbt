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

///|
fn report_sample(source : String, target : String) -> PlanRow {
  {
    source,
    target,
    status: "ready",
    reason: "分类 / 重命名",
    category: "文档",
  }
}

///|
test "MoonBit CSV reports quote data and prevent spreadsheet formulas" {
  let rows = [report_sample("=SUM(1,2).txt", "a,\"b\".txt")]
  let csv = report_csv(rows)
  assert_true(csv.has_prefix("\u{FEFF}"))
  assert_true(csv.contains("\"'=SUM(1,2).txt\""))
  assert_true(csv.contains("\"a,\"\"b\"\".txt\""))
  assert_true(csv.contains("分类 / 重命名"))
}

///|
test "MoonBit Markdown reports escape tables and flatten line breaks" {
  let rows = [{ ..report_sample("a|b", "folder/file"), reason: "line\nbreak" }]
  let text = report_markdown("2026-09-15", rows)
  assert_true(text.contains("a\\|b"))
  assert_true(text.contains("line break"))
  assert_true(text.contains("实际执行会再次检查"))
}

///|
test "machine report has an explicit schema version" {
  let text = report_machine_json("2026-09-15", [report_sample("a.txt", "文档/a.txt")])
  assert_true(text.contains("\"schemaVersion\":1"))
  assert_true(text.contains("文档/a.txt"))
}

///|
test "machine report preserves plan identity options and summary" {
  let input = (
    #|{"format":"json","plan":{"id":"plan-1","created":"2026-09-15","rows":[{"source":"a.txt","target":"文档/a.txt","status":"ready","reason":"分类","category":"文档"}],"options":{"classify":"type"},"summary":{"ready":1}}}
  )
  let envelope = @json.parse(report_json(input)) catch { _ => Json::null() }
  let content = match envelope {
    Object(fields) => match fields.get("content") { Some(String(text)) => text; _ => "" }
    _ => ""
  }
  assert_true(content.contains("\"id\":\"plan-1\""))
  assert_true(content.contains("\"options\":{\"classify\":\"type\"}"))
  assert_true(content.contains("\"summary\":{\"ready\":1}"))
}

///|
test "report boundary rejects unsupported formats and malformed rows" {
  assert_true(report_json("{broken").contains("error"))
  assert_true(report_json("{\"format\":\"xml\",\"rows\":[]}").contains("不支持"))
  assert_true(report_json("{\"format\":\"csv\",\"rows\":[{\"source\":\"\",\"target\":\"x\"}]}").contains("不能为空"))
}

///|
test "decimal file-size arithmetic remains exact beyond Int range" {
  assert_eq(normalize_decimal("00042"), Some("42"))
  assert_eq(normalize_decimal("12x"), None)
  assert_eq(decimal_add("99999999999999999999", "1"), "100000000000000000000")
  assert_eq(decimal_subtract("100000000000000000000", "1"), Some("99999999999999999999"))
  assert_eq(decimal_multiply_small("99999999999999999999", 9), Some("899999999999999999991"))
  assert_true(decimal_compare("10000000000000000000", "9999999999999999999") > 0)
}

///|
test "decimal percentage handles empty and bounded ratios" {
  assert_eq(decimal_percent_floor("1", "4"), Some(25))
  assert_eq(decimal_percent_floor("0", "4"), Some(0))
  assert_eq(decimal_percent_floor("4", "4"), Some(100))
  assert_eq(decimal_percent_floor("5", "4"), None)
  assert_eq(decimal_percent_floor("1", "0"), None)
}

///|
test "duplicate candidates group exact sizes and hashes deterministically" {
  let files = [
    { ..sample("z.txt"), size: "004", hash: "ABC" },
    { ..sample("a.txt"), size: "4", hash: "abc" },
    { ..sample("other.txt"), size: "4", hash: "different" },
  ]
  let groups = sort_duplicate_groups(duplicate_candidates(files))
  assert_eq(groups, [["a.txt", "z.txt"]])
  assert_eq(validate_candidate_groups(files, groups), [])
}

///|
test "duplicate candidates ignore missing digests and reject duplicate paths" {
  let missing = { ..sample("missing.txt"), hash: "" }
  assert_eq(duplicate_candidates([missing, missing]), [])
  let repeated = [sample("same.txt"), sample("same.txt")]
  let groups = duplicate_candidates(repeated)
  assert_true(validate_candidate_groups(repeated, groups).length() > 0)
}

///|
test "duplicate JSON boundary returns candidate groups" {
  let input = (
    #|{"files":[{"path":"b","name":"b","month":"2026-09","size":"1","hash":"x"},{"path":"a","name":"a","month":"2026-09","size":"1","hash":"x"}]}
  )
  let result = duplicate_candidates_json(input)
  assert_true(result.contains("\"a\""))
  assert_true(result.contains("\"b\""))
  assert_true(duplicate_candidates_json("bad").contains("error"))
}

///|
test "transaction preparation keeps only unique ready scanned paths" {
  let id = "12345678-1234-1234-1234-123456789abc"
  let rows = [
    report_sample("a.txt", "new/a.txt"),
    { ..report_sample("b.txt", "new/b.txt"), status: "excluded" },
  ]
  let (operations, errors) = prepare_transaction(id, rows, ["a.txt", "b.txt"])
  assert_eq(errors, [])
  assert_eq(operations.length(), 1)
  assert_eq(operations[0].stage, ".filenest/stage/" + id + "/0")
  assert_eq(operations[0].phase, "pending")
}

///|
test "transaction preparation rejects injected and duplicate targets" {
  let id = "12345678-1234-1234-1234-123456789abc"
  let duplicate = [
    report_sample("a.txt", "same.txt"),
    report_sample("b.txt", "same.txt"),
  ]
  let (_, duplicate_errors) = prepare_transaction(id, duplicate, ["a.txt", "b.txt"])
  assert_true(duplicate_errors.join(" ").contains("重复源或目标"))
  let injected = [report_sample("a.txt", "../outside.txt")]
  let (_, path_errors) = prepare_transaction(id, injected, ["a.txt"])
  assert_true(path_errors.join(" ").contains("目标路径不合法"))
}

///|
test "transaction state machine accepts only durable transitions" {
  assert_eq(transaction_transition("pending", "stage"), Some("staged"))
  assert_eq(transaction_transition("staged", "apply-start"), Some("applying"))
  assert_eq(transaction_transition("applying", "apply-finish"), Some("done"))
  assert_eq(transaction_transition("pending", "apply-finish"), None)
  assert_eq(transaction_reconciled_phase("applying", false), Some("staged"))
  assert_eq(transaction_reconciled_phase("undo-staging", true), Some("restaging"))
}

///|
test "journal validation fixes stage names and schedules undo passes" {
  let id = "12345678-1234-1234-1234-123456789abc"
  let operations : Array[TransactionOperation] = [
    { source: "a.txt", target: "new/a.txt", stage: ".filenest/stage/" + id + "/0", phase: "done" },
    { source: "b.txt", target: "new/b.txt", stage: ".filenest/stage/" + id + "/1", phase: "staged" },
    { source: "c.txt", target: "new/c.txt", stage: ".filenest/stage/" + id + "/2", phase: "pending" },
  ]
  assert_eq(validate_transaction_journal(id, operations), [])
  let (validate, restage, restore, targets) = transaction_undo_plan(operations)
  assert_eq(validate, [0, 1])
  assert_eq(restage, [0])
  assert_eq(restore, [0, 1])
  assert_eq(targets, ["new/a.txt"])
  let modified = operations.copy()
  modified[0] = { ..modified[0], stage: ".filenest/stage/wrong/0" }
  assert_true(validate_transaction_journal(id, modified).length() > 0)
}

///|
test "transaction JSON boundaries reject malformed requests" {
  assert_true(transaction_prepare_json("bad").contains("error"))
  assert_true(transaction_phase_json("{\"phase\":\"pending\",\"event\":\"apply-finish\"}").contains("error"))
  let valid = transaction_phase_json("{\"phase\":\"pending\",\"event\":\"stage\"}")
  assert_true(valid.contains("staged"))
  let blocked = (
    #|{"id":"12345678-1234-1234-1234-123456789abc","plan":[],"scanned":[],"historyStatuses":["interrupted"]}
  )
  assert_true(transaction_prepare_json(blocked).contains("未完成批次"))
}

///|
test "inventory analysis uses exact totals and stable distributions" {
  let files = [
    { ..sample("notes.txt"), size: "10", hash: "a" },
    { ..sample("archive/notes-copy.txt"), size: "10", hash: "a" },
    { ..sample("photo.JPG"), size: "1048576", hash: "b" },
  ]
  let analysis = analyze_inventory(files, [["notes.txt", "archive/notes-copy.txt"]])
  assert_eq(analysis.total_files, 3)
  assert_eq(analysis.total_bytes, "1048596")
  assert_eq(analysis.reclaimable_bytes, "10")
  assert_eq(analysis.duplicate_files, 2)
  assert_eq(analysis.extensions[0].extension, ".txt")
  assert_eq(analysis.categories[0].category, "文档")
  assert_true(analysis.recommendations.join(" ").contains("重复副本"))
}

///|
test "analysis classifies size bands folders depth and hidden files" {
  assert_eq(analysis_size_band("0"), "空文件")
  assert_eq(analysis_size_band("1048575"), "小于 1 MiB")
  assert_eq(analysis_size_band("1048576"), "1–100 MiB")
  assert_eq(analysis_size_band("1073741824"), "至少 1 GiB")
  assert_eq(analysis_folder("one/two/file.txt"), "one")
  assert_eq(analysis_folder("file.txt"), "（根目录）")
  assert_eq(analysis_depth("one/two/file.txt"), 2)
  let hidden = { ..sample(".secret"), size: "0" }
  let result = analyze_inventory([hidden], [])
  assert_eq(result.hidden_files, 1)
  assert_eq(result.size_bands[0].count, 1)
}

///|
test "analysis largest files sorts exact decimal sizes" {
  let files = [
    { ..sample("small.bin"), size: "99999999999999999999" },
    { ..sample("large.bin"), size: "100000000000000000000" },
    { ..sample("same-b.bin"), size: "5" },
    { ..sample("same-a.bin"), size: "5" },
  ]
  let largest = analysis_largest_files(files)
  assert_eq(largest[0].path, "large.bin")
  assert_eq(largest[1].path, "small.bin")
  assert_eq(largest[2].path, "same-a.bin")
}

///|
test "empty inventory analysis returns a useful recommendation" {
  let result = analyze_inventory([], [])
  assert_eq(result.total_files, 0)
  assert_eq(result.total_bytes, "0")
  assert_true(result.recommendations[0].contains("没有"))
}

///|
test "analysis JSON boundary rejects bad inventory and emits schema" {
  assert_true(analyze_inventory_json("bad").contains("error"))
  let invalid = #|{"files":[{"path":"a","name":"a","size":"x","hash":"h"}],"duplicates":[]}
  assert_true(analyze_inventory_json(invalid).contains("error"))
  let valid = #|{"files":[{"path":"a.txt","name":"a.txt","size":"1","hash":"h"}],"duplicates":[]}
  let result = analyze_inventory_json(valid)
  assert_true(result.contains("\"schemaVersion\":1"))
  assert_true(result.contains("\"totalFiles\":1"))
}

///|
fn saved(path : String, size : String, hash : String) -> SnapshotFile {
  { path, name: base_name(path), month: "2026-09", size, hash }
}

///|
test "snapshot diff distinguishes unchanged modified added and removed" {
  let before = [
    saved("same.txt", "1", "a"),
    saved("edit.txt", "2", "b"),
    saved("gone.txt", "3", "c"),
  ]
  let after = [
    saved("same.txt", "1", "a"),
    saved("edit.txt", "5", "changed"),
    saved("new.txt", "4", "d"),
  ]
  let result = compare_snapshots(before, after)
  assert_eq(result.summary.unchanged, 1)
  assert_eq(result.summary.modified, 1)
  assert_eq(result.summary.removed, 1)
  assert_eq(result.summary.added, 1)
  assert_eq(result.summary.bytes_added, "7")
  assert_eq(result.summary.bytes_removed, "3")
  assert_eq(result.summary.net_bytes, "+4")
}

///|
test "snapshot diff recognizes content moved to a new path" {
  let before = [saved("old/name.txt", "42", "digest")]
  let after = [saved("new/name.txt", "42", "digest")]
  let result = compare_snapshots(before, after)
  assert_eq(result.summary.moved, 1)
  assert_eq(result.summary.added, 0)
  assert_eq(result.summary.removed, 0)
  assert_eq(result.changes[0].kind, "moved")
  assert_eq(result.changes[0].before_path, "old/name.txt")
  assert_eq(result.changes[0].after_path, "new/name.txt")
}

///|
test "snapshot comparison stays exact beyond integer file sizes" {
  let before = [saved("huge.bin", "99999999999999999999", "old")]
  let after = [saved("huge.bin", "100000000000000000000", "new")]
  let result = compare_snapshots(before, after)
  assert_eq(result.summary.bytes_added, "1")
  assert_eq(result.summary.net_bytes, "+1")
  assert_eq(result.changes[0].bytes_changed, "1")
}

///|
test "snapshot validation rejects duplicate unsafe and inconsistent paths" {
  assert_true(validate_snapshot_files([saved("../bad.txt", "1", "x")]).length() > 0)
  assert_true(validate_snapshot_files([saved("folder/a.txt", "1", "x"), saved("FOLDER/A.TXT", "1", "y")]).length() > 0)
  let inconsistent : SnapshotFile = { path: "folder/a.txt", name: "b.txt", month: "", size: "1", hash: "x" }
  assert_true(validate_snapshot_files([inconsistent]).length() > 0)
}

///|
test "snapshot JSON boundaries create and compare versioned documents" {
  let input = (
    #|{"created":"2026-09-15","files":[{"path":"a.txt","name":"a.txt","month":"2026-09","size":"1","hash":"x"}]}
  )
  let snapshot = create_snapshot_json(input)
  assert_true(snapshot.contains("\"schemaVersion\":1"))
  let comparison = compare_snapshot_json(
    "{\"snapshot\":" + snapshot + ",\"current\":{\"files\":[{\"path\":\"a.txt\",\"name\":\"a.txt\",\"month\":\"2026-09\",\"size\":\"1\",\"hash\":\"x\"}]}}",
  )
  assert_true(comparison.contains("\"unchanged\":1"))
  assert_true(compare_snapshot_json("bad").contains("error"))
}

///|
test "rule tokenizer supports quotes escapes comments and empty values" {
  let (tokens, error) = tokenize_rule_line("rename replace \"old name\" \"new\\nname\" # note")
  assert_eq(error, None)
  assert_eq(tokens, ["rename", "replace", "old name", "new\nname"])
  let (empty, empty_error) = tokenize_rule_line("rename prefix \"\"")
  assert_eq(empty_error, None)
  assert_eq(empty, ["rename", "prefix", ""])
}

///|
test "rule tokenizer reports malformed quotes and escapes" {
  let (_, quote_error) = tokenize_rule_line("rename prefix \"open")
  assert_true(quote_error is Some(_))
  let (_, escape_error) = tokenize_rule_line("rename prefix \"bad\\q\"")
  assert_true(escape_error is Some(_))
}

///|
test "rule file compiles scan planning rename and category settings" {
  let source = (
    #|scan recursive off
    #|scan hidden on
    #|scan extensions ".JPG,png,jpg"
    #|scan exclude "cache files"
    #|classify custom
    #|conflict number
    #|sort size
    #|sequence start 20 width 4
    #|rename replace "old" "new"
    #|rename extension_lower
    #|category extension "jpg,png" "图片归档"
  )
  let (config, errors) = compile_rule_file(source)
  assert_eq(errors, [])
  assert_eq(config.recursive, false)
  assert_eq(config.hidden, true)
  assert_eq(config.extensions, ["jpg", "png"])
  assert_eq(config.exclude, ["cache files"])
  assert_eq(config.options.classify, "custom")
  assert_eq(config.options.sequence_start, 20)
  assert_eq(config.options.sequence_width, 4)
  assert_eq(config.options.rules.length(), 2)
  assert_eq(config.options.categories[0].folder, "图片归档")
}

///|
test "rule compiler returns line-numbered diagnostics together" {
  let source = (
    #|classify magic
    #|scan hidden maybe
    #|rename replace only-one
    #|unknown value
  )
  let (_, errors) = compile_rule_file(source)
  assert_eq(errors.length(), 4)
  assert_true(errors[0].contains("第 1 行"))
  assert_true(errors[3].contains("第 4 行"))
}

///|
test "rule extensions normalize dots case and duplicates" {
  assert_eq(rule_extensions(".JPG, png, jpg, .PDF"), ["jpg", "png", "pdf"])
  assert_eq(rule_extensions(" , "), [])
}

///|
test "rule JSON boundary emits compatible options" {
  let result = parse_rules_json("classify month\nrename number \"旅行_\"\nsequence start 8 width 2")
  assert_true(result.contains("\"classify\":\"month\""))
  assert_true(result.contains("\"sequenceStart\":\"8\""))
  assert_true(result.contains("\"kind\":\"number\""))
  assert_true(parse_rules_json("classify bad").contains("error"))
}

///|
test "application configuration normalizes defaults and integer strings" {
  let (config, errors) = decode_application_options({
    "classify": "month",
    "sequenceStart": "42",
    "sequenceWidth": 4,
    "recursive": false,
    "hidden": true,
  })
  assert_eq(errors, [])
  assert_eq(config.planning.classify, "month")
  assert_eq(config.planning.sequence_start, 42)
  assert_eq(config.planning.sequence_width, 4)
  assert_eq(config.recursive, false)
  assert_eq(config.hidden, true)
}

///|
test "configuration lists deduplicate while preserving first occurrence" {
  let input = (
    #|{"extensions":["jpg","png","jpg"],"exclude":["cache","cache"],"excluded":["a","a"],"quarantine":[]}
  )
  let result = validate_options_json(input)
  assert_true(result.contains("\"extensions\":[\"jpg\",\"png\"]"))
  assert_true(result.contains("\"exclude\":[\"cache\"]"))
  assert_true(result.contains("\"excluded\":[\"a\"]"))
}

///|
test "configuration rejects fractional ranges arrays and unknown choices" {
  assert_true(validate_options_json("{\"sequenceStart\":1.5}").contains("整数"))
  assert_true(validate_options_json("{\"extensions\":\"jpg\"}").contains("格式错误"))
  assert_true(validate_options_json("{\"classify\":\"magic\"}").contains("不支持"))
  assert_true(validate_options_json("{\"rules\":[{\"kind\":\"magic\"}]}").contains("未知命名规则"))
}

///|
test "template validation trims names and removes file selections" {
  let input = (
    #|{"name":"  我的模板  ","options":{"excluded":["a.txt"],"quarantine":["b.txt"]}}
  )
  let result = validate_template_json(input)
  assert_true(result.contains("\"name\":\"我的模板\""))
  assert_true(result.contains("\"excluded\":[]"))
  assert_true(result.contains("\"quarantine\":[]"))
  assert_true(validate_template_json("{\"name\":\"   \",\"options\":{}}").contains("不能为空"))
}

///|
test "MoonBit owns normalized defaults and built-in templates" {
  let result = configuration_defaults_json("")
  assert_true(result.contains("\"defaultOptions\""))
  assert_true(result.contains("下载文件夹"))
  assert_true(result.contains("旅行照片"))
  assert_true(result.contains("课程资料"))
  assert_true(result.contains("扫描件编号"))
}

///|
test "duplicate advisor prefers original-looking shallow paths" {
  let files = [
    { ..sample("资料/report.txt"), size: "10", hash: "same" },
    { ..sample("资料/备份/report 副本.txt"), size: "10", hash: "same" },
    { ..sample("report copy.txt"), size: "10", hash: "same" },
  ]
  let groups = [["资料/备份/report 副本.txt", "report copy.txt", "资料/report.txt"]]
  let advice = advise_duplicate_groups(files, groups)
  assert_eq(advice.length(), 1)
  assert_eq(advice[0].keeper, "资料/report.txt")
  assert_eq(advice[0].reclaimable_bytes, "20")
  assert_true(advice[0].reason.contains("副本"))
}

///|
test "duplicate advisor uses depth length and natural order as tie breakers" {
  let files = [
    { ..sample("deep/folder/a.txt"), size: "1", hash: "x" },
    { ..sample("a10.txt"), size: "1", hash: "x" },
    { ..sample("a2.txt"), size: "1", hash: "x" },
  ]
  let advice = advise_duplicate_groups(files, [files.map(file => file.path)])
  assert_eq(advice[0].keeper, "a2.txt")
  assert_eq(advice[0].quarantine, ["a10.txt", "deep/folder/a.txt"])
}

///|
test "analysis includes non-destructive duplicate keeper advice" {
  let files = [
    { ..sample("original.txt"), size: "4", hash: "x" },
    { ..sample("original 副本.txt"), size: "4", hash: "x" },
  ]
  let analysis = analyze_inventory(files, [["original.txt", "original 副本.txt"]])
  assert_eq(analysis.duplicate_advice[0].keeper, "original.txt")
  let input = (
    #|{"files":[{"path":"original.txt","name":"original.txt","month":"","size":"4","hash":"x"},{"path":"original 副本.txt","name":"original 副本.txt","month":"","size":"4","hash":"x"}],"duplicates":[["original.txt","original 副本.txt"]]}
  )
  let boundary = duplicate_advice_json(input)
  assert_true(boundary.contains("\"keeper\":\"original.txt\""))
}
