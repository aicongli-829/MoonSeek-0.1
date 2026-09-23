///|
fn fuzzy_separator(char : Char) -> Bool {
  char.is_whitespace() ||
  char.to_int() == 92 ||
  ['-', '_', '.', '/', '(', ')', '[', ']'].contains(char)
}

///|
fn fuzzy_normalize(source : String) -> String {
  let result = StringBuilder()
  for char in source.to_lower() {
    if char.is_ascii_alphabetic() ||
      char.is_ascii_digit() ||
      cjk_character(char) {
      result.write_char(char)
    }
  }
  result.to_string()
}

///|
fn fuzzy_word_initials(source : String) -> String {
  let result = StringBuilder()
  let mut boundary = true
  for char in source.to_lower() {
    if fuzzy_separator(char) {
      boundary = true
    } else if boundary {
      result.write_char(char)
      boundary = false
    }
  }
  result.to_string()
}

///|
fn subsequence_score(query : String, candidate : String) -> Double {
  if query == "" || candidate == "" {
    return 0.0
  }
  let query_chars = query.to_array()
  let candidate_chars = candidate.to_array()
  let mut query_index = 0
  let mut last_match = -2
  let mut score = 0.0
  for index, char in candidate_chars {
    if query_index < query_chars.length() && char == query_chars[query_index] {
      score = score + 1.0
      if index == last_match + 1 {
        score = score + 0.7
      }
      if index == 0 {
        score = score + 1.2
      }
      last_match = index
      query_index = query_index + 1
    }
  }
  if query_index != query_chars.length() {
    0.0
  } else {
    score / candidate_chars.length().max(1).to_double()
  }
}

///|
fn bounded_edit_distance(left : String, right : String, limit : Int) -> Int {
  let a = left.to_array()
  let b = right.to_array()
  if (a.length() - b.length()).abs() > limit {
    return limit + 1
  }
  let previous = Array::make(b.length() + 1, 0)
  let current = Array::make(b.length() + 1, 0)
  for index = 0; index <= b.length(); index = index + 1 {
    previous[index] = index
  }
  for row = 1; row <= a.length(); row = row + 1 {
    current[0] = row
    let mut row_minimum = row
    for column = 1; column <= b.length(); column = column + 1 {
      let substitution = previous[column - 1] +
        (if a[row - 1] == b[column - 1] { 0 } else { 1 })
      current[column] = (previous[column] + 1)
        .min(current[column - 1] + 1)
        .min(substitution)
      row_minimum = row_minimum.min(current[column])
    }
    if row_minimum > limit {
      return limit + 1
    }
    for column = 0; column <= b.length(); column = column + 1 {
      previous[column] = current[column]
    }
  }
  previous[b.length()]
}

///|
/// Return a conservative filename similarity bonus. Exact, prefix and word
/// boundary matches dominate; edit distance is only used for short typos.
fn fuzzy_filename_score(
  query_source : String,
  filename_source : String,
) -> Double {
  let query = fuzzy_normalize(query_source)
  let filename = fuzzy_normalize(filename_source)
  if query.length() < 2 || filename == "" {
    return 0.0
  }
  if filename == query {
    return 14.0
  }
  if filename.has_prefix(query) {
    return 11.0 - (filename.length() - query.length()).to_double() * 0.02
  }
  if filename.contains(query) {
    return 8.0
  }
  let initials = fuzzy_word_initials(filename_source)
  if initials == query {
    return 7.0
  }
  let subsequence = subsequence_score(query, filename)
  if subsequence >= 0.45 {
    return 2.0 + subsequence * 4.0
  }
  if query.length() <= 24 && filename.length() <= 80 {
    let limit = if query.length() <= 5 { 1 } else { 2 }
    let distance = bounded_edit_distance(query, filename, limit)
    if distance <= limit {
      return 5.0 - distance.to_double()
    }
  }
  0.0
}

///|
pub fn fuzzy_score_json(source : String) -> String {
  try {
    let input = search_parse(source, "fuzzy request")
    let query = search_text(input, "query", "")
    let candidate = search_text(input, "candidate", "")
    ({ "score": fuzzy_filename_score(query, candidate).to_string() } : Json).stringify()
  } catch {
    error => search_error(error.to_string())
  }
}
