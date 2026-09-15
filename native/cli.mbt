///|
let cli_help =
  #|FileNest · MoonBit 本地文件整理
  #|
  #|用法：
  #|  moon run --target native cmd/filenest -- serve [--port 4173] [--root 文件夹]
  #|  moon run --target native cmd/filenest -- scan <文件夹> [--config rules.json]
  #|  moon run --target native cmd/filenest -- analyze <文件夹> [--config rules.json]
  #|  moon run --target native cmd/filenest -- preview <文件夹> [--config rules.json | --rules rules.fnrules] [--csv]
  #|  moon run --target native cmd/filenest -- apply <文件夹> [--config rules.json | --rules rules.fnrules] --yes
  #|  moon run --target native cmd/filenest -- snapshot <文件夹> [--output snapshot.json]
  #|  moon run --target native cmd/filenest -- diff <文件夹> --snapshot snapshot.json
  #|  moon run --target native cmd/filenest -- history <文件夹>
  #|  moon run --target native cmd/filenest -- undo <文件夹> <批次ID> --yes
  #|
  #|所有文件操作由 MoonBit Native 执行。计划先预览、不覆盖目标，并保存在 .filenest/history。

///|
fn argument_after(args : Array[String], flag : String) -> String? {
  for index, value in args {
    if value == flag && index + 1 < args.length() {
      return Some(args[index + 1])
    }
  }
  None
}

///|
async fn cli_options(args : Array[String]) -> Json {
  let config = argument_after(args, "--config")
  let rules = argument_after(args, "--rules")
  guard !(config is Some(_) && rules is Some(_)) else {
    fail("--config 和 --rules 只能选择一种")
  }
  let raw = match (config, rules) {
    (Some(path), _) => read_text(path)
    (_, Some(path)) => {
      let parsed = parse_document(
        @core.parse_rules_json(read_text(path)),
        "规则结果",
      )
      match json_field(parsed, "error") {
        String(message) => fail(message)
        _ => json_field(parsed, "options").stringify()
      }
    }
    _ => {
      let defaults = parse_document(
        @core.configuration_defaults_json("{}"),
        "默认设置",
      )
      json_field(defaults, "defaultOptions").stringify()
    }
  }
  let validated = parse_document(
    @core.validate_options_json(raw),
    "设置结果",
  )
  match json_field(validated, "error") {
    String(message) => fail(message)
    _ => json_field(validated, "options")
  }
}

///|
async fn cli_scan(root : String, options : Json) -> Json {
  let result = parse_document(
    scan_json(root, options.stringify()),
    "扫描结果",
  )
  match json_field(result, "error") {
    String(message) => fail(message)
    _ => result
  }
}

///|
fn cli_plan(scanned : Json, options : Json) -> Json raise {
  let inventory = json_field(scanned, "inventory")
  let result = parse_document(
    @core.plan_bundle_json(
      (
        {
          "files": json_field(inventory, "files"),
          "occupied": json_field(inventory, "occupied"),
          "directories": json_field(inventory, "directories"),
          "duplicates": json_field(inventory, "duplicates"),
          "options": options,
        } : Json).stringify(),
    ),
    "预览结果",
  )
  match json_field(result, "error") {
    String(message) => fail(message)
    _ =>
      {
        "id": operation_id(),
        "created": @env.now().to_string(),
        "rows": json_field(result, "rows"),
        "options": options,
        "summary": json_field(result, "summary"),
      }
  }
}

///|
fn print_result(value : Json) -> Unit {
  println(value.stringify(indent=2))
}

///|
/// Execute the complete command-line surface without a Node.js launcher.
pub async fn run_cli(args : Array[String]) -> Unit {
  let commands = [
    "serve", "scan", "analyze", "preview", "apply", "snapshot", "diff", "history",
    "undo",
  ]
  let mut command_index : (Int, String)? = None
  for index, value in args {
    if command_index is None && commands.contains(value) {
      command_index = Some((index, value))
    }
  }
  if args.contains("--version") {
    println("FileNest 0.2.0 · MoonBit Native")
    return
  }
  let (index, command) = match command_index {
    Some(pair) => pair
    None => {
      println(cli_help)
      return
    }
  }
  if command == "serve" {
    let port = match argument_after(args, "--port") {
      Some(text) =>
        @string.parse_int(text) catch {
          _ => fail("端口必须是整数")
        }
      None => 4173
    }
    guard port >= 1024 && port <= 65535 else {
      fail("端口必须在 1024–65535 之间")
    }
    serve(port, initial_root=argument_after(args, "--root").unwrap_or(""))
    return
  }
  guard index + 1 < args.length() else { fail("缺少文件夹路径") }
  let root_input = args[index + 1]
  if command == "history" {
    print_result(parse_document(history_json(root_input), "历史记录"))
    return
  }
  if command == "undo" {
    guard index + 2 < args.length() && args.contains("--yes") else {
      fail("撤销需要批次 ID 和 --yes")
    }
    print_result(
      parse_document(undo_json(root_input, args[index + 2]), "撤销结果"),
    )
    return
  }
  let options = cli_options(args)
  let scanned = cli_scan(root_input, options)
  let inventory = json_field(scanned, "inventory")
  match command {
    "scan" => print_result(inventory)
    "analyze" =>
      print_result(
        parse_document(
          @core.analyze_inventory_json(
            (
              {
                "files": json_field(inventory, "files"),
                "duplicates": json_field(inventory, "duplicates"),
              } : Json).stringify(),
          ),
          "分析结果",
        ),
      )
    "snapshot" => {
      let snapshot = parse_document(
        @core.create_snapshot_json(
          (
            {
              "created": @env.now().to_string(),
              "files": json_field(inventory, "files"),
            } : Json).stringify(),
        ),
        "快照结果",
      )
      match argument_after(args, "--output") {
        Some(path) => {
          write_text(path, snapshot.stringify(indent=2) + "\n")
          println("快照已保存：" + path)
        }
        None => print_result(snapshot)
      }
    }
    "diff" => {
      let snapshot_path = argument_after(args, "--snapshot").unwrap_or_else(() => {
        fail("diff 需要 --snapshot")
      })
      print_result(
        parse_document(
          @core.compare_snapshot_json(
            (
              {
                "snapshot": parse_document(read_text(snapshot_path), "快照"),
                "current": { "files": json_field(inventory, "files") },
              } : Json).stringify(),
          ),
          "对比结果",
        ),
      )
    }
    "preview" | "apply" => {
      let plan = cli_plan(scanned, options)
      if command == "preview" {
        if args.contains("--csv") {
          let report = parse_document(
            @core.report_json(
              ({ "format": "csv", "plan": plan } : Json).stringify(),
            ),
            "CSV 报告",
          )
          println(json_text(report, "content", ""))
        } else {
          print_result(plan)
        }
      } else {
        guard args.contains("--yes") else {
          print_result(plan)
          fail("以上仅为预览。执行需要显式传入 --yes")
        }
        print_result(
          parse_document(
            execute_json(
              json_text(scanned, "root", ""),
              plan.stringify(),
              inventory.stringify(),
            ),
            "执行结果",
          ),
        )
      }
    }
    _ => fail("未知命令")
  }
}
