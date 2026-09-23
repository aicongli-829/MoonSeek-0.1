///|
priv struct NumberRange {
  minimum : Int64?
  maximum : Int64?
}

///|
fn empty_number_range() -> NumberRange {
  { minimum: None, maximum: None, }
}

///|
fn decimal_bytes(number : String, multiplier : Int64) -> Int64? {
  let parsed = @string.parse_double(number) catch { _ => return None }
  if parsed < 0.0 {
    None
  } else {
    Some((parsed * multiplier.to_double()).to_int64())
  }
}

///|
fn parse_byte_count(source : String) -> Int64? {
  let clean = source.trim().to_owned().to_lower().replace_all(old=" ", new="")
  if clean == "" {
    return None
  }
  let units : Array[(String, Int64)] = [
    ("tib", 1099511627776L),
    ("tb", 1000000000000L),
    ("gib", 1073741824L),
    ("gb", 1000000000L),
    ("mib", 1048576L),
    ("mb", 1000000L),
    ("kib", 1024L),
    ("kb", 1000L),
    ("bytes", 1L),
    ("byte", 1L),
    ("b", 1L),
  ]
  for (suffix, multiplier) in units {
    if clean.has_suffix(suffix) && clean.length() > suffix.length() {
      return decimal_bytes(
        clean[:clean.length() - suffix.length()].to_owned(),
        multiplier,
      )
    }
  }
  decimal_bytes(clean, 1L)
}

///|
fn named_size_range(source : String) -> NumberRange? {
  match source.trim().to_owned().to_lower() {
    "empty" => Some({ minimum: Some(0L), maximum: Some(0L), })
    "tiny" => Some({ minimum: None, maximum: Some(100L * 1024L), })
    "small" => Some({ minimum: None, maximum: Some(1024L * 1024L), })
    "medium" =>
      Some({
        minimum: Some(1024L * 1024L),
        maximum: Some(100L * 1024L * 1024L),
      })
    "large" =>
      Some({
        minimum: Some(100L * 1024L * 1024L),
        maximum: Some(1024L * 1024L * 1024L),
      })
    "huge" => Some({ minimum: Some(1024L * 1024L * 1024L), maximum: None, })
    _ => None
  }
}

///|
fn parse_size_range(source : String) -> NumberRange? {
  let clean = source.trim().to_owned().to_lower()
  match named_size_range(clean) {
    Some(range) => return Some(range)
    None => ()
  }
  if clean.has_prefix(">=") {
    parse_byte_count(clean[2:].to_owned()).map(value => {
      minimum: Some(value),
      maximum: None,
    })
  } else if clean.has_prefix(">") {
    parse_byte_count(clean[1:].to_owned()).map(value => {
      minimum: Some(value + 1L),
      maximum: None,
    })
  } else if clean.has_prefix("<=") {
    parse_byte_count(clean[2:].to_owned()).map(value => {
      minimum: None,
      maximum: Some(value),
    })
  } else if clean.has_prefix("<") {
    parse_byte_count(clean[1:].to_owned()).map(value => {
      minimum: None,
      maximum: Some((value - 1L).max(0L)),
    })
  } else if clean.contains("..") {
    let pieces = clean.split("..").map(item => item.to_owned()).collect()
    guard pieces.length() == 2 else { return None }
    let minimum = parse_byte_count(pieces[0])
    let maximum = parse_byte_count(pieces[1])
    if minimum is None && maximum is None {
      None
    } else {
      Some({ minimum, maximum, })
    }
  } else {
    parse_byte_count(clean).map(value => {
      minimum: Some(value),
      maximum: Some(value),
    })
  }
}

///|
fn number_in_range(value : Int64, range : NumberRange) -> Bool {
  let above_minimum = match range.minimum {
    Some(minimum) => value >= minimum
    None => true
  }
  let below_maximum = match range.maximum {
    Some(maximum) => value <= maximum
    None => true
  }
  above_minimum && below_maximum
}

///|
fn range_to_json(range : NumberRange) -> Json {
  {
    "minimum": match range.minimum {
      Some(value) => value.to_string()
      None => Json::null()
    },
    "maximum": match range.maximum {
      Some(value) => value.to_string()
      None => Json::null()
    },
  }
}
