///|
fn cjk_character(char : Char) -> Bool {
  let code = char.to_int()
  (code >= 0x3400 && code <= 0x4dbf) ||
  (code >= 0x4e00 && code <= 0x9fff) ||
  (code >= 0xf900 && code <= 0xfaff)
}

///|
fn ascii_word_character(char : Char) -> Bool {
  char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '_'
}

///|
fn push_search_token(tokens : Array[String], builder : StringBuilder) -> Unit {
  let value = builder.to_string().to_lower()
  if value != "" && value.length() <= 64 {
    tokens.push(value)
  }
}

///|
/// Tokenize mixed English, numbers and CJK text without a runtime dictionary.
/// CJK unigrams make every name searchable; adjacent bigrams improve precision.
pub fn search_tokens(source : String) -> Array[String] {
  let tokens : Array[String] = []
  let mut ascii = StringBuilder()
  let cjk_run : Array[Char] = []
  fn flush_ascii() {
    push_search_token(tokens, ascii)
    ascii = StringBuilder()
  }
  fn flush_cjk() {
    for index, char in cjk_run {
      tokens.push(char.to_string())
      if index + 1 < cjk_run.length() {
        tokens.push(char.to_string() + cjk_run[index + 1].to_string())
      }
    }
    cjk_run.clear()
  }
  for char in source {
    if ascii_word_character(char) {
      flush_cjk()
      ascii.write_char(char.to_ascii_lowercase())
    } else if cjk_character(char) {
      flush_ascii()
      cjk_run.push(char)
    } else {
      flush_ascii()
      flush_cjk()
    }
  }
  flush_ascii()
  flush_cjk()
  tokens
}

///|
fn unique_search_tokens(source : String) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let result : Array[String] = []
  for token in search_tokens(source) {
    if !seen.contains(token) {
      seen[token] = true
      result.push(token)
    }
  }
  result
}

///|
pub fn tokenize_search_json(source : String) -> String {
  try {
    let input = search_parse(source, "tokenize request")
    let text = search_text(input, "text", "")
    ({ "tokens": search_tokens(text).to_json() } : Json).stringify()
  } catch {
    error => search_error(error.to_string())
  }
}
