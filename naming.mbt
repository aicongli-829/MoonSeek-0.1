///|
/// Digit-aware comparison without parsing unbounded digit runs as integers.
/// Ties are broken by original spelling for deterministic plans.
pub fn natural_compare(left : String, right : String) -> Int {
  let a = left.to_lower()
  let b = right.to_lower()
  let mut i = 0
  let mut j = 0
  while i < a.length() && j < b.length() {
    let ad = a[i] >= 48 && a[i] <= 57
    let bd = b[j] >= 48 && b[j] <= 57
    if ad && bd {
      let ai = i
      let bj = j
      while i < a.length() && a[i] >= 48 && a[i] <= 57 {
        i = i + 1
      }
      while j < b.length() && b[j] >= 48 && b[j] <= 57 {
        j = j + 1
      }
      let an = a[ai:i].trim_start(chars="0").to_owned()
      let bn = b[bj:j].trim_start(chars="0").to_owned()
      if an.length() != bn.length() {
        return an.length().compare(bn.length())
      }
      if an != bn {
        return an.compare(bn)
      }
      if i - ai != j - bj {
        return (i - ai).compare(j - bj)
      }
    } else {
      if a[i] != b[j] {
        return a[i].compare(b[j])
      }
      i = i + 1
      j = j + 1
    }
  }
  if a.length() != b.length() {
    a.length().compare(b.length())
  } else {
    left.compare(right)
  }
}

///|
pub fn padded_number(number : Int, width : Int) -> String {
  let mut output = number.to_string()
  while output.length() < width {
    output = "0" + output
  }
  output
}

///|
/// Collapse whitespace rather than deleting word boundaries.
pub fn normalize_spaces(value : String) -> String {
  let output = StringBuilder()
  let mut pending = false
  let mut started = false
  for ch in value.iter() {
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '　' {
      if started {
        pending = true
      }
    } else {
      if pending {
        output.write_string(" ")
      }
      output.write_char(ch)
      pending = false
      started = true
    }
  }
  output.to_string()
}

///|
/// Naming rules operate on the stem; extension changes require an explicit rule.
pub fn rename_file(
  name : String,
  rules : Array[RenameRule],
  sequence : Int,
  width : Int,
) -> String {
  let (initial, initial_ext) = split_extension(name)
  let mut stem = initial
  let mut ext = initial_ext
  for rule in rules {
    match rule.kind {
      "prefix" => stem = rule.value + stem
      "suffix" => stem = stem + rule.value
      "replace" =>
        if rule.value != "" {
          stem = stem.replace_all(old=rule.value, new=rule.replacement)
        }
      "remove" =>
        if rule.value != "" {
          stem = stem.replace_all(old=rule.value, new="")
        }
      "lower" => stem = stem.to_lower()
      "upper" => stem = stem.to_upper()
      "spaces" => stem = normalize_spaces(stem)
      "separator" =>
        stem = normalize_spaces(stem).replace_all(old=" ", new=rule.value)
      "extension_lower" => ext = ext.to_lower()
      "number" => stem = rule.value + padded_number(sequence, width)
      "number_suffix" =>
        stem = stem + rule.value + padded_number(sequence, width)
      "regex" => {
        let re = @string.Regex(rule.value) catch { _ => continue }
        stem = re.replace_by(stem, _ => rule.replacement[:]).to_owned()
      }
      _ => ()
    }
  }
  stem + ext
}

///|
pub fn validate_options(options : Options) -> Array[String] {
  let errors = []
  if !["none", "type", "month", "type_month", "custom"].contains(
      options.classify,
    ) {
    errors.push("未知分类方式")
  }
  if !["skip", "number"].contains(options.conflict) {
    errors.push("未知冲突处理方式")
  }
  if !["name", "path", "month", "size"].contains(options.sort) {
    errors.push("未知排序方式")
  }
  if options.sequence_start < 0 || options.sequence_start > 1000000 {
    errors.push("起始编号必须在 0 到 1000000 之间")
  }
  if options.sequence_width < 1 || options.sequence_width > 8 {
    errors.push("编号位数必须在 1 到 8 之间")
  }
  if options.rules.length() > 30 || options.categories.length() > 30 {
    errors.push("最多允许 30 条命名规则和 30 条分类规则")
  }
  for rule in options.rules {
    if ![
        "prefix", "suffix", "replace", "remove", "lower", "upper", "spaces", "separator",
        "extension_lower", "number", "number_suffix", "regex",
      ].contains(rule.kind) {
      errors.push("未知命名规则：" + rule.kind)
    }
    if ["replace", "remove", "regex"].contains(rule.kind) && rule.value == "" {
      errors.push("查找内容不能为空")
    }
    if rule.kind == "regex" {
      try @string.Regex(rule.value) |> ignore catch {
        _ => errors.push("正则表达式不合法：" + rule.value)
      }
    }
    if rule.value.length() > 200 || rule.replacement.length() > 200 {
      errors.push("规则内容过长")
    }
  }
  for rule in options.categories {
    if !["extension", "keyword"].contains(rule.kind) {
      errors.push("未知自定义分类规则")
    }
    if rule.value.trim().is_empty() {
      errors.push("分类匹配内容不能为空")
    }
    if path_error(rule.folder) is Some(error) {
      errors.push("分类目录：" + error)
    }
  }
  errors
}
