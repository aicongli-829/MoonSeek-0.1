///|
/// Convert Unix days to a Gregorian year/month using Howard Hinnant's civil
/// calendar algorithm. This avoids locale and timezone dependencies in plans.
#cfg(platform="windows")
fn filesystem_epoch_offset() -> Int64 {
  11644473600L
}

///|
#cfg(not(platform="windows"))
fn filesystem_epoch_offset() -> Int64 {
  0L
}

///|
fn unix_seconds(filesystem_seconds : Int64) -> Int64 {
  filesystem_seconds - filesystem_epoch_offset()
}

///|
fn month_from_epoch(seconds : Int64) -> String {
  let z = unix_seconds(seconds) / 86400L + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let day_of_era = z - era * 146097L
  let year_of_era = (
      day_of_era -
      day_of_era / 1460L +
      day_of_era / 36524L -
      day_of_era / 146096L
    ) /
    365L
  let mut year = year_of_era + era * 400L
  let day_of_year = day_of_era -
    (365L * year_of_era + year_of_era / 4L - year_of_era / 100L)
  let month_prime = (5L * day_of_year + 2L) / 153L
  let month = month_prime + (if month_prime < 10L { 3L } else { -9L })
  if month <= 2L {
    year = year + 1L
  }
  let month_text = month.to_string()
  year.to_string() +
  "-" +
  (if month_text.length() == 1 { "0" + month_text } else { month_text })
}
