///|
priv struct SearchIgnoreRule {
  pattern : String
  negative : Bool
  directory_only : Bool
  anchored : Bool
}

///|
fn normalize_ignore_path(source : String) -> String {
  source.replace_all(old="\\", new="/").trim_start(chars=['/']).to_owned()
}

///|
fn parse_search_ignore(source : String) -> Array[SearchIgnoreRule] {
  let rules : Array[SearchIgnoreRule] = []
  for raw in source.split("\n") {
    let mut line = raw.trim().trim_end(chars=['\r']).to_owned()
    if line == "" || line.has_prefix("#") {
      continue
    }
    let negative = line.has_prefix("!")
    if negative {
      line = line[1:].to_owned()
    }
    let anchored = line.has_prefix("/")
    let directory_only = line.has_suffix("/")
    line = line
      .trim_start(chars=['/'])
      .trim_end(chars=['/'])
      .to_owned()
      .replace_all(old="\\", new="/")
    if line != "" {
      rules.push({ pattern: line, negative, directory_only, anchored, })
    }
  }
  rules
}

///|
fn wildcard_segment(pattern : String, value : String) -> Bool {
  let pattern = pattern.to_lower().to_array()
  let value = value.to_lower().to_array()
  let mut pattern_index = 0
  let mut value_index = 0
  let mut star = -1
  let mut retry = 0
  while value_index < value.length() {
    if pattern_index < pattern.length() &&
      (
        pattern[pattern_index] == '?' ||
        pattern[pattern_index] == value[value_index]
      ) {
      pattern_index = pattern_index + 1
      value_index = value_index + 1
    } else if pattern_index < pattern.length() && pattern[pattern_index] == '*' {
      star = pattern_index
      retry = value_index
      pattern_index = pattern_index + 1
    } else if star >= 0 {
      pattern_index = star + 1
      retry = retry + 1
      value_index = retry
    } else {
      return false
    }
  }
  while pattern_index < pattern.length() && pattern[pattern_index] == '*' {
    pattern_index = pattern_index + 1
  }
  pattern_index == pattern.length()
}

///|
fn split_ignore_path(source : String) -> Array[String] {
  normalize_ignore_path(source)
  .split("/")
  .filter(piece => piece != "")
  .map(piece => piece.to_owned())
  .collect()
}

///|
fn wildcard_path(pattern : String, value : String) -> Bool {
  let patterns = split_ignore_path(pattern)
  let values = split_ignore_path(value)
  let table : Array[Array[Bool]] = []
  for row = 0; row <= patterns.length(); row = row + 1 {
    table.push(Array::make(values.length() + 1, false))
  }
  table[0][0] = true
  for pattern_index = 0
      pattern_index < patterns.length()
      pattern_index = pattern_index + 1 {
    let pattern_piece = patterns[pattern_index]
    for value_count = 0
        value_count <= values.length()
        value_count = value_count + 1 {
      if pattern_piece == "**" {
        let without_segment = table[pattern_index][value_count]
        let with_segment = value_count > 0 &&
          table[pattern_index + 1][value_count - 1]
        table[pattern_index + 1][value_count] = without_segment || with_segment
      } else if value_count > 0 &&
        table[pattern_index][value_count - 1] &&
        wildcard_segment(pattern_piece, values[value_count - 1]) {
        table[pattern_index + 1][value_count] = true
      }
    }
  }
  table[patterns.length()][values.length()]
}

///|
fn ignore_rule_matches(
  rule : SearchIgnoreRule,
  relative : String,
  is_directory : Bool,
) -> Bool {
  if rule.directory_only && !is_directory {
    return false
  }
  let path = normalize_ignore_path(relative)
  if rule.anchored || rule.pattern.contains("/") {
    wildcard_path(rule.pattern, path)
  } else {
    split_ignore_path(path).any(segment => {
      wildcard_segment(rule.pattern, segment)
    })
  }
}

///|
fn search_path_ignored(
  relative : String,
  is_directory : Bool,
  rules : Array[SearchIgnoreRule],
) -> Bool {
  let mut ignored = false
  for rule in rules {
    if ignore_rule_matches(rule, relative, is_directory) {
      ignored = !rule.negative
    }
  }
  ignored
}

///|
async fn load_search_ignore_rules(root : String) -> Array[SearchIgnoreRule] {
  let path = native_path(root, ".moonseekignore")
  if @fs.exists(path) {
    parse_search_ignore(read_text(path))
  } else {
    []
  }
}
