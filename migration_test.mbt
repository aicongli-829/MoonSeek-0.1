///|
fn migration_step_for_test(
  id : String,
  kind : String,
  source? : String = "",
  target? : String = "",
  path? : String = "",
) -> MigrationStep {
  {
    id,
    kind,
    source,
    target,
    path,
    content: "",
    find: if kind == "replace" {
      "old"
    } else {
      ""
    },
    replacement: "new",
    expected_sha256: "",
    optional: false,
  }
}

///|
test "migration manifest builds a contiguous plan" {
  let first : Migration = {
    id: "v1",
    from_version: 0,
    to_version: 1,
    description: "create layout",
    steps: [migration_step_for_test("cache", "mkdir", path="cache/v1")],
  }
  let second : Migration = {
    id: "v2",
    from_version: 1,
    to_version: 2,
    description: "move settings",
    steps: [
      migration_step_for_test(
        "settings",
        "move",
        source="config.old",
        target="config/app.toml",
      ),
    ],
  }
  let manifest : MigrationManifest = {
    format_version: 1,
    project: "demo-app",
    migrations: [second, first],
  }
  let (result, errors) = build_migration_plan(manifest, 0, Some(2))
  assert_eq(errors.length(), 0)
  guard result is Some(plan) else { fail("expected plan") }
  inspect(plan.target_version, content="2")
  assert_eq(plan.migrations.map(item => item.id), ["v1", "v2"])
  inspect(plan.steps.length(), content="2")
}

///|
test "migration planning detects gaps and invalid target boundaries" {
  let manifest : MigrationManifest = {
    format_version: 1,
    project: "demo-app",
    migrations: [
      {
        id: "v2",
        from_version: 1,
        to_version: 2,
        description: "gap",
        steps: [migration_step_for_test("data", "mkdir", path="data")],
      },
    ],
  }
  let (_, gap_errors) = build_migration_plan(manifest, 0, Some(2))
  assert_true(gap_errors.any(message => message.contains("中断")))
  let jump : MigrationManifest = {
    format_version: 1,
    project: "demo-app",
    migrations: [
      {
        id: "jump",
        from_version: 0,
        to_version: 2,
        description: "jump",
        steps: [migration_step_for_test("data", "mkdir", path="data")],
      },
    ],
  }
  let (_, boundary_errors) = build_migration_plan(jump, 0, Some(1))
  assert_true(boundary_errors.any(message => message.contains("边界")))
}

///|
test "migration validation rejects unsafe and ambiguous operations" {
  let invalid : MigrationManifest = {
    format_version: 1,
    project: "demo-app",
    migrations: [
      {
        id: "v1",
        from_version: 0,
        to_version: 1,
        description: "invalid",
        steps: [
          migration_step_for_test(
            "escape",
            "move",
            source="../secret",
            target="safe/file",
          ),
          migration_step_for_test("empty-find", "replace", path="app.toml"),
        ],
      },
    ],
  }
  let errors = validate_migration_manifest(invalid)
  assert_true(errors.any(message => message.contains("路径不安全")))
}

///|
test "migration JSON boundary returns an auditable flattened plan" {
  let input =
    #|{
    #|  "manifest": {
    #|    "formatVersion": 1,
    #|    "project": "demo-app",
    #|    "migrations": [{
    #|      "id": "v1", "fromVersion": 0, "toVersion": 1,
    #|      "steps": [
    #|        {"id": "layout", "op": "mkdir", "path": "data/v1"},
    #|        {"id": "marker", "op": "write", "path": "data/version", "content": "1"}
    #|      ]
    #|    }]
    #|  },
    #|  "currentVersion": 0
    #|}
  let output = @json.parse(migration_plan_json(input))
  guard output is Object(fields) else { fail("expected object") }
  guard fields.get("targetVersion") is Some(Number(target, ..)) else {
    fail("expected targetVersion")
  }
  guard fields.get("stepCount") is Some(Number(count, ..)) else {
    fail("expected stepCount")
  }
  assert_eq(target.to_int(), 1)
  assert_eq(count.to_int(), 2)
}
