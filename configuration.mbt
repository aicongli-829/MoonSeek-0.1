///| Full application configuration combines deterministic planner options with
/// scan settings owned by the operating-system adapter.
pub(all) struct ApplicationOptions {
  planning : Options
  recursive : Bool
  hidden : Bool
  extensions : Array[String]
  exclude : Array[String]
} derive(Debug)

///| Return whether a JSON value is an object, including an empty object.
fn configuration_object(value : Json) -> Bool {
  value is Object(_)
}

///| Optional text field with a strict byte limit.
fn configuration_text(
  value : Json,
  key : String,
  fallback : String,
  limit : Int,
  label : String,
  errors : Array[String],
) -> String {
  match field(value, key) {
    Null => fallback
    String(text) => {
      if text.length() > limit {
        errors.push(label + "必须是长度不超过 " + limit.to_string() + " 的文字")
        fallback
      } else {
        text
      }
    }
    _ => {
      errors.push(label + "必须是长度不超过 " + limit.to_string() + " 的文字")
      fallback
    }
  }
}

///| Optional Boolean field with the same defaults as the original UI.
fn configuration_bool(value : Json, key : String, fallback : Bool) -> Bool {
  match field(value, key) {
    true => true
    false => false
    _ => fallback
  }
}

///| Parse an integer from a JSON string or number and reject fractions.
fn configuration_integer(
  value : Json,
  key : String,
  fallback : Int,
  minimum : Int,
  maximum : Int,
  label : String,
  errors : Array[String],
) -> Int {
  let raw = field(value, key)
  let parsed : Int? = match raw {
    Null => Some(fallback)
    String(text) => try { Some(@string.parse_int(text)) } catch { _ => None }
    Number(number, ..) => {
      let integer = number.to_int()
      if integer.to_double() == number { Some(integer) } else { None }
    }
    _ => None
  }
  match parsed {
    Some(number) if number >= minimum && number <= maximum => number
    _ => {
      errors.push(label + "必须是 " + minimum.to_string() + "–" + maximum.to_string() + " 的整数")
      fallback
    }
  }
}

///| Decode, validate and deduplicate a list of strings.
fn configuration_string_list(
  value : Json,
  key : String,
  limit : Int,
  text_limit : Int,
  label : String,
  errors : Array[String],
) -> Array[String] {
  let result = []
  match field(value, key) {
    Null => result
    Array(items) => {
      if items.length() > limit {
        errors.push(label + "数量过多或格式错误")
        return result
      }
      for item in items {
        match item {
          String(text) if text.length() <= text_limit => if !result.contains(text) { result.push(text) }
          _ => errors.push(label + "必须是长度不超过 " + text_limit.to_string() + " 的文字")
        }
      }
      result
    }
    _ => {
      errors.push(label + "数量过多或格式错误")
      result
    }
  }
}

///| Decode rename rules from an untrusted JSON configuration.
fn configuration_rename_rules(value : Json, errors : Array[String]) -> Array[RenameRule] {
  let result = []
  match field(value, "rules") {
    Null => result
    Array(items) => {
      if items.length() > 30 {
        errors.push("最多允许 30 条命名规则")
        return result
      }
      for raw in items {
        if !configuration_object(raw) {
          errors.push("命名规则必须是对象")
          continue
        }
        let kind = configuration_text(raw, "kind", "", 40, "命名规则类型", errors)
        let value = configuration_text(raw, "value", "", 200, "规则内容", errors)
        let replacement = configuration_text(raw, "replacement", "", 200, "替换内容", errors)
        if ![
          "prefix", "suffix", "replace", "remove", "lower", "upper",
          "spaces", "separator", "extension_lower", "number", "number_suffix",
          "regex",
        ].contains(kind) {
          errors.push("未知命名规则")
        } else {
          result.push({ kind, value, replacement })
        }
      }
      result
    }
    _ => {
      errors.push("最多允许 30 条命名规则")
      result
    }
  }
}

///| Decode first-match custom category rules.
fn configuration_category_rules(value : Json, errors : Array[String]) -> Array[CategoryRule] {
  let result = []
  match field(value, "categories") {
    Null => result
    Array(items) => {
      if items.length() > 30 {
        errors.push("最多允许 30 条分类规则")
        return result
      }
      for raw in items {
        if !configuration_object(raw) {
          errors.push("分类规则必须是对象")
          continue
        }
        let kind = configuration_text(raw, "kind", "", 40, "分类匹配方式", errors)
        let value = configuration_text(raw, "value", "", 200, "分类匹配内容", errors)
        let folder = configuration_text(raw, "folder", "", 200, "分类文件夹", errors)
        if !["extension", "keyword"].contains(kind) {
          errors.push("分类匹配方式不支持：" + kind)
        } else {
          result.push({ kind, value, folder })
        }
      }
      result
    }
    _ => {
      errors.push("最多允许 30 条分类规则")
      result
    }
  }
}

///| Validate every UI, CLI and template option in MoonBit.
pub fn decode_application_options(value : Json) -> (ApplicationOptions, Array[String]) {
  let errors = []
  let fallback = default_options()
  if !configuration_object(value) {
    errors.push("设置必须是对象")
    return ({ planning: fallback, recursive: true, hidden: false, extensions: [], exclude: [] }, errors)
  }
  let classify = configuration_text(value, "classify", "type", 40, "分类方式", errors)
  let conflict = configuration_text(value, "conflict", "skip", 40, "冲突方式", errors)
  let sort = configuration_text(value, "sort", "name", 40, "排序", errors)
  if !["none", "type", "month", "type_month", "custom"].contains(classify) {
    errors.push("分类方式不支持：" + classify)
  }
  if !["skip", "number"].contains(conflict) {
    errors.push("冲突方式不支持：" + conflict)
  }
  if !["name", "path", "month", "size"].contains(sort) {
    errors.push("排序不支持：" + sort)
  }
  let sequence_start = configuration_integer(value, "sequenceStart", 1, 0, 1000000, "起始编号", errors)
  let sequence_width = configuration_integer(value, "sequenceWidth", 3, 1, 8, "编号宽度", errors)
  let extensions = configuration_string_list(value, "extensions", 100, 1000, "扩展名", errors)
  let exclude = configuration_string_list(value, "exclude", 100, 1000, "排除目录", errors)
  let excluded = configuration_string_list(value, "excluded", 10000, 1000, "排除文件", errors)
  let quarantine = configuration_string_list(value, "quarantine", 10000, 1000, "隔离文件", errors)
  let rules = configuration_rename_rules(value, errors)
  let categories = configuration_category_rules(value, errors)
  let planning : Options = {
    classify,
    conflict,
    sequence_start,
    sequence_width,
    sort,
    rules,
    categories,
    excluded,
    quarantine,
  }
  errors.push_iter(validate_options(planning).iter())
  ({
    planning,
    recursive: configuration_bool(value, "recursive", true),
    hidden: configuration_bool(value, "hidden", false),
    extensions,
    exclude,
  }, errors)
}

///| Camel-case application options returned to JavaScript.
fn application_options_json(config : ApplicationOptions) -> Json {
  {
    "classify": config.planning.classify,
    "conflict": config.planning.conflict,
    "sort": config.planning.sort,
    "sequenceStart": config.planning.sequence_start.to_string(),
    "sequenceWidth": config.planning.sequence_width.to_string(),
    "recursive": config.recursive,
    "hidden": config.hidden,
    "extensions": config.extensions.to_json(),
    "exclude": config.exclude.to_json(),
    "excluded": config.planning.excluded.to_json(),
    "quarantine": config.planning.quarantine.to_json(),
    "rules": config.planning.rules.to_json(),
    "categories": config.planning.categories.to_json(),
  }
}

///| Validate arbitrary application options supplied by HTTP, CLI or templates.
pub fn validate_options_json(input : String) -> String {
  let document = @json.parse(input) catch {
    _ => return ({ "error": "设置不是合法 JSON" } : Json).stringify()
  }
  let (config, errors) = decode_application_options(document)
  if errors.length() > 0 {
    return ({ "error": errors.join("；") } : Json).stringify()
  }
  ({ "options": application_options_json(config) } : Json).stringify()
}

///| Validate a user template and remove inventory-specific selections.
pub fn validate_template_json(input : String) -> String {
  let document = @json.parse(input) catch {
    _ => return ({ "error": "模板不是合法 JSON" } : Json).stringify()
  }
  if !configuration_object(document) {
    return ({ "error": "模板必须是对象" } : Json).stringify()
  }
  let errors = []
  let name = configuration_text(document, "name", "", 40, "模板名称", errors).trim().to_owned()
  let description = configuration_text(document, "description", "我的整理规则", 120, "模板说明", errors)
  if name == "" { errors.push("模板名称不能为空") }
  let (config, option_errors) = decode_application_options(field(document, "options"))
  errors.push_iter(option_errors.iter())
  let clean : ApplicationOptions = {
    ..config,
    planning: { ..config.planning, excluded: [], quarantine: [] },
  }
  if errors.length() > 0 {
    return ({ "error": errors.join("；") } : Json).stringify()
  }
  ({ "template": { "name": name, "description": description, "options": application_options_json(clean) } } : Json).stringify()
}

///| Built-in templates originate in MoonBit so every frontend uses identical
/// normalized defaults and rule values.
pub fn configuration_defaults_json(_input : String) -> String {
  let base : ApplicationOptions = {
    planning: default_options(),
    recursive: true,
    hidden: false,
    extensions: [],
    exclude: [],
  }
  let downloads : ApplicationOptions = {
    ..base,
    planning: { ..base.planning, rules: [{ kind: "extension_lower", value: "", replacement: "" }] },
  }
  let travel : ApplicationOptions = {
    ..base,
    extensions: ["jpg", "jpeg", "png", "heic", "webp"],
    planning: {
      ..base.planning,
      classify: "month",
      conflict: "number",
      rules: [
        { kind: "number", value: "旅行_", replacement: "" },
        { kind: "extension_lower", value: "", replacement: "" },
      ],
    },
  }
  let course : ApplicationOptions = {
    ..base,
    planning: {
      ..base.planning,
      conflict: "number",
      rules: [
        { kind: "remove", value: " (副本)", replacement: "" },
        { kind: "remove", value: "（副本）", replacement: "" },
        { kind: "spaces", value: "", replacement: "" },
        { kind: "extension_lower", value: "", replacement: "" },
      ],
    },
  }
  let scans : ApplicationOptions = {
    ..base,
    extensions: ["jpg", "png", "pdf"],
    planning: {
      ..base.planning,
      classify: "none",
      conflict: "number",
      rules: [{ kind: "number", value: "扫描_第", replacement: "" }],
    },
  }
  ({
    "defaultOptions": application_options_json(base),
    "builtInTemplates": [
      { "name": "下载文件夹", "description": "按类型归档，统一扩展名，保留原文件名", "options": application_options_json(downloads) },
      { "name": "旅行照片", "description": "只选择图片，按修改月份分类并编号", "options": application_options_json(travel) },
      { "name": "课程资料", "description": "清除“副本”，规范空格，按类型分类", "options": application_options_json(course) },
      { "name": "扫描件编号", "description": "保持文件夹位置，按自然顺序重新编号", "options": application_options_json(scans) },
    ],
  } : Json).stringify()
}
