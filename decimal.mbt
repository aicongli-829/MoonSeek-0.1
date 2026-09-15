///| File sizes arrive from JavaScript as decimal strings so values above the
/// 32-bit MoonBit Int range remain exact. These helpers implement the small
/// subset of non-negative decimal arithmetic required by inventory summaries.

///|
/// Validate and canonicalize an unsigned decimal value.
pub fn normalize_decimal(value : String) -> String? {
  let text = value.trim().to_owned()
  if text == "" {
    return None
  }
  for character in text {
    let code = character.to_int()
    if code < 48 || code > 57 {
      return None
    }
  }
  let normalized = text.trim_start(chars="0").to_owned()
  if normalized == "" {
    Some("0")
  } else {
    Some(normalized)
  }
}

///|
/// Compare unsigned decimals without converting them to bounded integers.
pub fn decimal_compare(left : String, right : String) -> Int {
  let a = normalize_decimal(left).unwrap_or("0")
  let b = normalize_decimal(right).unwrap_or("0")
  if a.length() != b.length() {
    a.length().compare(b.length())
  } else {
    a.compare(b)
  }
}

///|
/// Add two unsigned decimal values exactly.
pub fn decimal_add(left : String, right : String) -> String {
  let a = normalize_decimal(left).unwrap_or("0")
  let b = normalize_decimal(right).unwrap_or("0")
  let symbols = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
  let mut i = a.length() - 1
  let mut j = b.length() - 1
  let mut carry = 0
  let mut output = ""
  while i >= 0 || j >= 0 || carry > 0 {
    let x = if i >= 0 { a[i].to_int() - 48 } else { 0 }
    let y = if j >= 0 { b[j].to_int() - 48 } else { 0 }
    let total = x + y + carry
    output = symbols[total % 10] + output
    carry = total / 10
    i = i - 1
    j = j - 1
  }
  output
}

///|
/// Add an array of unsigned decimal values.
pub fn decimal_sum(values : Array[String]) -> String {
  let mut total = "0"
  for value in values {
    total = decimal_add(total, value)
  }
  total
}

///|
/// Multiply an unsigned decimal by a small non-negative integer. This is used
/// for projected storage calculations and never loses precision.
pub fn decimal_multiply_small(value : String, factor : Int) -> String? {
  if factor < 0 {
    return None
  }
  let input = normalize_decimal(value)
  if input is None {
    return None
  }
  if factor == 0 {
    return Some("0")
  }
  let text = input.unwrap()
  let symbols = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
  let mut index = text.length() - 1
  let mut carry = 0
  let mut output = ""
  while index >= 0 || carry > 0 {
    let digit = if index >= 0 { text[index].to_int() - 48 } else { 0 }
    let total = digit * factor + carry
    output = symbols[total % 10] + output
    carry = total / 10
    index = index - 1
  }
  Some(output)
}

///|
/// Subtract right from left. A negative result is rejected.
pub fn decimal_subtract(left : String, right : String) -> String? {
  let a = normalize_decimal(left)
  let b = normalize_decimal(right)
  if a is None || b is None {
    return None
  }
  let x = a.unwrap()
  let y = b.unwrap()
  if decimal_compare(x, y) < 0 {
    return None
  }
  let symbols = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
  let mut i = x.length() - 1
  let mut j = y.length() - 1
  let mut borrow = 0
  let mut output = ""
  while i >= 0 {
    let mut digit = x[i].to_int() - 48 - borrow
    let other = if j >= 0 { y[j].to_int() - 48 } else { 0 }
    if digit < other {
      digit = digit + 10
      borrow = 1
    } else {
      borrow = 0
    }
    output = symbols[digit - other] + output
    i = i - 1
    j = j - 1
  }
  normalize_decimal(output)
}

///|
/// Decimal percentage rounded down to a whole number. The numerator must not
/// exceed the denominator; the implementation avoids floating-point drift.
pub fn decimal_percent_floor(numerator : String, denominator : String) -> Int? {
  let top = normalize_decimal(numerator)
  let bottom = normalize_decimal(denominator)
  if top is None || bottom is None || bottom.unwrap() == "0" {
    return None
  }
  if decimal_compare(top.unwrap(), bottom.unwrap()) > 0 {
    return None
  }
  let mut result = 0
  let mut remaining = decimal_multiply_small(top.unwrap(), 100).unwrap()
  while result < 100 && decimal_compare(remaining, bottom.unwrap()) >= 0 {
    remaining = decimal_subtract(remaining, bottom.unwrap()).unwrap()
    result = result + 1
  }
  Some(result)
}
