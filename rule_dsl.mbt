///|
/// Result of compiling a readable .fnrules file. Scan-only settings live next
/// to the existing deterministic planning options.
pub(all) struct RuleFileConfig {
  options : Options
  recursive : Bool
  hidden : Bool
  extensions : Array[String]
  exclude : Array[String]
} derive(Debug)

///|
/// Append a decoded escape inside quoted rule text.
fn rule_escape(builder : StringBuilder, character : Char) -> Bool {
  match character {
    'n' => {
      builder.write_char('\n')
      true
    }
    'r' => {
      builder.write_char('\r')
      true
    }
    't' => {
      builder.write_char('\t')
      true
    }
    '"' => {
      builder.write_char('"')
      true
    }
    '\\' => {
      builder.write_char('\\')
      true
    }
    _ => false
  }
}

///|
/// Tokenize one line with shell-like quotes. A # outside quotes starts a
/// comment. This small grammar keeps rule files readable on every platform.
pub fn tokenize_rule_line(line : String) -> (Array[String], String?) {
  let tokens = []
  let mut current = StringBuilder()
  let mut quoted = false
  let mut escaping = false
  let mut active = false
  for character in line.iter() {
    if escaping {
      if !rule_escape(current, character) {
        return (
          tokens,
          Some("不支持的转义字符：\\" + character.to_string()),
        )
      }
      escaping = false
      active = true
      continue
    }
    if quoted && character == '\\' {
      escaping = true
      continue
    }
    if character == '"' {
      quoted = !quoted
      active = true
      continue
    }
    if !quoted && character == '#' {
      break
    }
    if !quoted && (character == ' ' || character == '\t') {
      if active {
        tokens.push(current.to_string())
        current = StringBuilder()
        active = false
      }
      continue
    }
    current.write_char(character)
    active = true
  }
  if escaping {
    return (tokens, Some("行尾缺少转义字符内容"))
  }
  if quoted {
    return (tokens, Some("引号没有闭合"))
  }
  if active {
    tokens.push(current.to_string())
  }
  (tokens, None)
}

///|
/// Human-readable diagnostic including one-based source line.
fn rule_diagnostic(line : Int, message : String) -> String {
  "第 " + line.to_string() + " 行：" + message
}

///|
/// Parse on/off consistently across scan settings.
fn rule_switch(value : String) -> Bool? {
  match value.to_lower() {
    "on" | "true" | "yes" | "开" => Some(true)
    "off" | "false" | "no" | "关" => Some(false)
    _ => None
  }
}

///|
/// Split a comma-separated extension list and remove leading dots.
pub fn rule_extensions(value : String) -> Array[String] {
  let result = []
  for item in value.split(",") {
    let text = item.trim().to_owned().to_lower()
    let extension = if text.has_prefix(".") {
      text[1:].to_owned()
    } else {
      text
    }
    if extension != "" && !result.contains(extension) {
      result.push(extension)
    }
  }
  result
}

///|
/// Add a rename command after validating its arity and operation name.
fn parse_rename_rule(tokens : Array[String]) -> (RenameRule?, String?) {
  if tokens.length() < 2 {
    return (None, Some("rename 后需要操作名称"))
  }
  let kind = tokens[1].to_lower()
  match kind {
    "lower" | "upper" | "spaces" | "extension_lower" => {
      if tokens.length() != 2 {
        return (None, Some(kind + " 不接受参数"))
      }
      (Some({ kind, value: "", replacement: "", }), None)
    }
    "prefix"
    | "suffix"
    | "remove"
    | "separator"
    | "number"
    | "number_suffix"
    | "regex" => {
      if tokens.length() != 3 {
        return (None, Some(kind + " 需要一个参数"))
      }
      (Some({ kind, value: tokens[2], replacement: "", }), None)
    }
    "replace" => {
      if tokens.length() != 4 {
        return (None, Some("replace 需要原文字和替换文字"))
      }
      (Some({ kind, value: tokens[2], replacement: tokens[3], }), None)
    }
    _ => (None, Some("未知 rename 操作：" + kind))
  }
}

///|
/// Add a custom category rule.
fn parse_category_rule(tokens : Array[String]) -> (CategoryRule?, String?) {
  if tokens.length() != 4 {
    return (
      None,
      Some("category 需要匹配方式、匹配内容和目标文件夹"),
    )
  }
  let kind = tokens[1].to_lower()
  if kind != "extension" && kind != "keyword" {
    return (None, Some("category 只支持 extension 或 keyword"))
  }
  if tokens[2] == "" || tokens[3] == "" {
    return (
      None,
      Some("category 的匹配内容和目标文件夹不能为空"),
    )
  }
  (Some({ kind, value: tokens[2], folder: tokens[3], }), None)
}

///|
/// Compile the complete rule source and return all diagnostics in one pass.
pub fn compile_rule_file(source : String) -> (RuleFileConfig, Array[String]) {
  let mut classify = "type"
  let mut conflict = "skip"
  let mut sort = "name"
  let mut sequence_start = 1
  let mut sequence_width = 3
  let mut recursive = true
  let mut hidden = false
  let extensions = []
  let excludes = []
  let rules = []
  let categories = []
  let errors = []
  let lines = source.split("\n").to_array()
  for line_index, raw_line in lines {
    let line_number = line_index + 1
    let line = raw_line.trim().to_owned()
    let (tokens, token_error) = tokenize_rule_line(line)
    if token_error is Some(message) {
      errors.push(rule_diagnostic(line_number, message))
      continue
    }
    if tokens.length() == 0 {
      continue
    }
    let command = tokens[0].to_lower()
    match command {
      "classify" =>
        if tokens.length() != 2 ||
          !["none", "type", "month", "type_month", "custom"].contains(tokens[1]) {
          errors.push(
            rule_diagnostic(
              line_number, "classify 需要 none、type、month、type_month 或 custom",
            ),
          )
        } else {
          classify = tokens[1]
        }
      "conflict" =>
        if tokens.length() != 2 || !["skip", "number"].contains(tokens[1]) {
          errors.push(
            rule_diagnostic(line_number, "conflict 需要 skip 或 number"),
          )
        } else {
          conflict = tokens[1]
        }
      "sort" =>
        if tokens.length() != 2 ||
          !["name", "path", "month", "size"].contains(tokens[1]) {
          errors.push(
            rule_diagnostic(
              line_number, "sort 需要 name、path、month 或 size",
            ),
          )
        } else {
          sort = tokens[1]
        }
      "sequence" =>
        if tokens.length() != 5 || tokens[1] != "start" || tokens[3] != "width" {
          errors.push(
            rule_diagnostic(
              line_number, "sequence 格式为 sequence start 数字 width 数字",
            ),
          )
        } else {
          let start = @string.parse_int(tokens[2]) catch { _ => -1 }
          let width = @string.parse_int(tokens[4]) catch { _ => -1 }
          if start < 0 || start > 1000000 || width < 1 || width > 8 {
            errors.push(
              rule_diagnostic(
                line_number, "编号起点需为 0–1000000，宽度需为 1–8",
              ),
            )
          } else {
            sequence_start = start
            sequence_width = width
          }
        }
      "scan" =>
        if tokens.length() < 3 {
          errors.push(
            rule_diagnostic(line_number, "scan 需要设置名和值"),
          )
        } else {
          match tokens[1].to_lower() {
            "recursive" =>
              match rule_switch(tokens[2]) {
                Some(value) =>
                  if tokens.length() == 3 {
                    recursive = value
                  } else {
                    errors.push(
                      rule_diagnostic(
                        line_number, "recursive 只接受一个开关值",
                      ),
                    )
                  }
                None =>
                  errors.push(
                    rule_diagnostic(line_number, "recursive 需要 on 或 off"),
                  )
              }
            "hidden" =>
              match rule_switch(tokens[2]) {
                Some(value) =>
                  if tokens.length() == 3 {
                    hidden = value
                  } else {
                    errors.push(
                      rule_diagnostic(
                        line_number, "hidden 只接受一个开关值",
                      ),
                    )
                  }
                None =>
                  errors.push(
                    rule_diagnostic(line_number, "hidden 需要 on 或 off"),
                  )
              }
            "extensions" =>
              if tokens.length() != 3 {
                errors.push(
                  rule_diagnostic(
                    line_number, "extensions 使用逗号分隔并写成一个参数",
                  ),
                )
              } else {
                extensions.clear()
                extensions.push_iter(rule_extensions(tokens[2]).iter())
              }
            "exclude" =>
              if tokens.length() != 3 || tokens[2] == "" {
                errors.push(
                  rule_diagnostic(
                    line_number, "exclude 需要一个相对目录",
                  ),
                )
              } else if !excludes.contains(tokens[2]) {
                excludes.push(tokens[2])
              }
            setting =>
              errors.push(
                rule_diagnostic(line_number, "未知 scan 设置：" + setting),
              )
          }
        }
      "rename" => {
        let (rule, error) = parse_rename_rule(tokens)
        match rule {
          Some(value) => rules.push(value)
          None => ()
        }
        match error {
          Some(message) => errors.push(rule_diagnostic(line_number, message))
          None => ()
        }
      }
      "category" => {
        let (rule, error) = parse_category_rule(tokens)
        match rule {
          Some(value) => categories.push(value)
          None => ()
        }
        match error {
          Some(message) => errors.push(rule_diagnostic(line_number, message))
          None => ()
        }
      }
      unknown =>
        errors.push(rule_diagnostic(line_number, "未知命令：" + unknown))
    }
  }
  if rules.length() > 30 {
    errors.push("命名规则不能超过 30 条")
  }
  if categories.length() > 30 {
    errors.push("分类规则不能超过 30 条")
  }
  let options : Options = {
    classify,
    conflict,
    sequence_start,
    sequence_width,
    sort,
    rules,
    categories,
    excluded: [],
    quarantine: [],
  }
  errors.push_iter(validate_options(options).iter())
  ({ options, recursive, hidden, extensions, exclude: excludes, }, errors)
}

///|
/// Serialize with the camelCase keys accepted by existing CLI and web options.
fn rule_file_config_json(config : RuleFileConfig) -> Json {
  {
    "classify": config.options.classify,
    "conflict": config.options.conflict,
    "sort": config.options.sort,
    "sequenceStart": config.options.sequence_start.to_string(),
    "sequenceWidth": config.options.sequence_width.to_string(),
    "recursive": config.recursive,
    "hidden": config.hidden,
    "extensions": config.extensions.to_json(),
    "exclude": config.exclude.to_json(),
    "excluded": config.options.excluded.to_json(),
    "quarantine": config.options.quarantine.to_json(),
    "rules": config.options.rules.to_json(),
    "categories": config.options.categories.to_json(),
  }
}

///|
/// JavaScript boundary accepts the rule source directly, avoiding a second
/// escaping layer for quotes and comments.
pub fn parse_rules_json(source : String) -> String {
  if source.length() > 100000 {
    return ({ "error": "规则文件不能超过 100,000 字符" } : Json).stringify()
  }
  let (config, errors) = compile_rule_file(source)
  if errors.length() > 0 {
    return ({ "error": errors.join("；") } : Json).stringify()
  }
  ({ "options": rule_file_config_json(config) } : Json).stringify()
}
