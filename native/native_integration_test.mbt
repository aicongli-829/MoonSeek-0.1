///|
async test "native scan confirms duplicate bytes" {
  let root = @fs.tmpdir(prefix="filenest-scan-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.mkdir(root + "/sub")
  @fs.write_file(root + "/one.txt", "same content", create_mode=CreateNew)
  @fs.write_file(root + "/sub/two.txt", "same content", create_mode=CreateNew)
  @fs.write_file(root + "/different.txt", "different", create_mode=CreateNew)
  let result = @json.parse(scan_json(root, "{}"))
  guard result
    is {
      "inventory": {
        "files": Array(files),
        "duplicates": Array([Array(group)]),
        ..
      },
      ..
    } else {
    fail("unexpected scan response")
  }
  assert_eq(files.length(), 3)
  assert_eq(group.length(), 2)
  @fs.rmdir(root, recursive=true)
}

///|
async test "native transaction applies and undoes reviewed rows" {
  let root = @fs.tmpdir(prefix="filenest-transaction-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.write_file(root + "/before.txt", "transaction", create_mode=CreateNew)
  let scanned = @json.parse(scan_json(root, "{}"))
  guard scanned is { "inventory": inventory, .. } else { fail("scan failed") }
  let plan : Json = {
    "rows": [
      {
        "source": "before.txt",
        "target": "文档/after.txt",
        "status": "ready",
        "reason": "test",
        "category": "文档",
      },
    ],
  }
  let applied = @json.parse(
    execute_json(root, plan.stringify(), inventory.stringify()),
  )
  guard applied is { "id": String(id), "status": String("completed"), .. } else {
    fail("execute failed")
  }
  assert_false(@fs.exists(root + "/before.txt"))
  assert_true(@fs.exists(root + "/文档/after.txt"))
  let undone = @json.parse(undo_json(root, id))
  guard undone is { "status": String("undone"), .. } else {
    fail("undo failed")
  }
  assert_true(@fs.exists(root + "/before.txt"))
  assert_false(@fs.exists(root + "/文档/after.txt"))
  @fs.rmdir(root, recursive=true)
}

///|
async test "versioned migration applies mixed steps and rolls them back" {
  let root = @fs.tmpdir(prefix="moonmigrate-transaction-")
  errdefer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.write_file(root + "/legacy.txt", "legacy", create_mode=CreateNew)
  @fs.write_file(root + "/seed.bin", b"seed", create_mode=CreateNew)
  @fs.write_file(root + "/settings.txt", "mode=old\n", create_mode=CreateNew)
  @fs.write_file(root + "/obsolete.tmp", "remove me", create_mode=CreateNew)
  let manifest =
    #|{
    #|  "formatVersion": 1,
    #|  "project": "integration-demo",
    #|  "migrations": [{
    #|    "id": "layout-v1",
    #|    "fromVersion": 0,
    #|    "toVersion": 1,
    #|    "steps": [
    #|      {"id":"directory", "op":"mkdir", "path":"data/v2"},
    #|      {"id":"move-legacy", "op":"move", "from":"legacy.txt", "to":"data/current.txt"},
    #|      {"id":"copy-seed", "op":"copy", "from":"seed.bin", "to":"data/v2/seed.bin"},
    #|      {"id":"write-version", "op":"write", "path":"version.txt", "content":"1\n"},
    #|      {"id":"update-settings", "op":"replace", "path":"settings.txt", "find":"mode=old", "replace":"mode=new"},
    #|      {"id":"retire-file", "op":"quarantine", "from":"obsolete.tmp"}
    #|    ]
    #|  }]
    #|}
  let preview = @json.parse(migration_preview_json(root, manifest, None))
  guard preview is { "ready": true, "actions": Array(actions), .. } else {
    fail("preview failed")
  }
  assert_eq(actions.length(), 6)
  let applied = @json.parse(migration_apply_json(root, manifest, None))
  guard applied is { "id": String(id), "status": String("completed"), .. } else {
    fail("migration failed")
  }
  assert_false(@fs.exists(root + "/legacy.txt"))
  assert_true(@fs.exists(root + "/data/current.txt"))
  assert_true(@fs.exists(root + "/data/v2/seed.bin"))
  inspect(read_text(root + "/settings.txt"), content="mode=new\n")
  assert_false(@fs.exists(root + "/obsolete.tmp"))
  let status = @json.parse(migration_status_json(root))
  guard status is { "state": { "version": Number(version, ..), .. }, .. } else {
    fail("status failed")
  }
  assert_eq(version.to_int(), 1)
  let rolled_back = @json.parse(migration_rollback_json(root, id))
  guard rolled_back is { "status": String("rolled-back"), .. } else {
    fail("rollback failed: " + rolled_back.stringify())
  }
  assert_true(@fs.exists(root + "/legacy.txt"))
  assert_false(@fs.exists(root + "/data/current.txt"))
  assert_false(@fs.exists(root + "/data/v2"))
  assert_false(@fs.exists(root + "/data"))
  assert_false(@fs.exists(root + "/version.txt"))
  inspect(read_text(root + "/settings.txt"), content="mode=old\n")
  assert_true(@fs.exists(root + "/obsolete.tmp"))
  @fs.rmdir(root, recursive=true)
}
