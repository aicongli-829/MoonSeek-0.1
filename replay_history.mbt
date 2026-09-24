///|
fn exchange_request(exchange : Json) -> Json {
  normalize_request(replay_field(exchange, "request"))
}

///|
fn exchange_response(exchange : Json) -> Json {
  replay_field(exchange, "response")
}

///|
fn exchange_matches_method(exchange : Json, methods : Array[String]) -> Bool {
  methods.length() == 0 ||
  methods
  .map(uppercase)
  .contains(uppercase(replay_text(exchange_request(exchange), "method", "GET")))
}

///|
fn exchange_matches_status(exchange : Json, statuses : Array[String]) -> Bool {
  if statuses.length() == 0 {
    return true
  }
  let status = replay_int(exchange_response(exchange), "status", 0)
  statuses.any(pattern => {
    let clean = pattern.trim().to_owned().to_lower()
    if clean.has_suffix("xx") && clean.length() == 3 {
      let group = @string.parse_int(clean[:1]) catch { _ => -1 }
      status / 100 == group
    } else if clean.contains("-") {
      let pieces = clean.split("-").map(x => x.to_owned()).collect()
      if pieces.length() != 2 {
        false
      } else {
        let minimum = @string.parse_int(pieces[0]) catch { _ => -1 }
        let maximum = @string.parse_int(pieces[1]) catch { _ => -1 }
        status >= minimum && status <= maximum
      }
    } else {
      status == (@string.parse_int(clean) catch { _ => -1 })
    }
  })
}

///|
fn exchange_matches_path(
  exchange : Json,
  pattern : String,
  mode : String,
) -> Bool {
  if pattern == "" {
    return true
  }
  let path = normalize_path(
    replay_text(exchange_request(exchange), "path", "/"),
  )
  match lowercase(mode) {
    "exact" => path == normalize_path(pattern)
    "prefix" => path.has_prefix(normalize_path(pattern))
    "wildcard" => wildcard_match(pattern, path)
    _ => lowercase(path).contains(lowercase(pattern))
  }
}

///|
fn exchange_matches_header(
  exchange : Json,
  name : String,
  value : String,
) -> Bool {
  if name == "" {
    return true
  }
  match header_value(exchange_request(exchange), name) {
    Some(actual) => value == "" || lowercase(actual).contains(lowercase(value))
    None => false
  }
}

///|
fn exchange_matches_body(exchange : Json, text : String) -> Bool {
  text == "" ||
  lowercase(replay_text(exchange_request(exchange), "body", "")).contains(
    lowercase(text),
  ) ||
  lowercase(replay_text(exchange_response(exchange), "body", "")).contains(
    lowercase(text),
  )
}

///|
fn exchange_matches_tag(exchange : Json, tags : Array[String]) -> Bool {
  if tags.length() == 0 {
    return true
  }
  let actual = replay_strings(exchange, "tags").map(lowercase)
  tags.map(lowercase).all(tag => actual.contains(tag))
}

///|
fn exchange_matches_time(
  exchange : Json,
  minimum : Int64,
  maximum : Int64,
) -> Bool {
  let value = replay_int64(exchange, "sequence", 0L)
  (minimum <= 0L || value >= minimum) && (maximum <= 0L || value <= maximum)
}

///|
fn exchange_matches_filter(exchange : Json, filter : Json) -> Bool {
  exchange_matches_method(exchange, replay_strings(filter, "methods")) &&
  exchange_matches_status(exchange, replay_strings(filter, "statuses")) &&
  exchange_matches_path(
    exchange,
    replay_text(filter, "path", ""),
    replay_text(filter, "pathMode", "contains"),
  ) &&
  exchange_matches_header(
    exchange,
    replay_text(filter, "headerName", ""),
    replay_text(filter, "headerValue", ""),
  ) &&
  exchange_matches_body(exchange, replay_text(filter, "body", "")) &&
  exchange_matches_tag(exchange, replay_strings(filter, "tags")) &&
  exchange_matches_time(
    exchange,
    replay_int64(filter, "sequenceFrom", 0L),
    replay_int64(filter, "sequenceTo", 0L),
  )
}

///|
fn exchange_summary(exchange : Json) -> Json {
  let request = request_summary(exchange_request(exchange))
  let response = exchange_response(exchange)
  {
    "id": replay_text(exchange, "id", replay_text(request, "id", "")),
    "sequence": replay_int64(exchange, "sequence", 0L).to_string(),
    "receivedAt": replay_text(
      exchange,
      "receivedAt",
      replay_text(request, "receivedAt", ""),
    ),
    "method": replay_text(request, "method", ""),
    "path": replay_text(request, "path", ""),
    "status": replay_int(response, "status", 0),
    "durationMs": replay_int64(response, "durationMs", 0L).to_string(),
    "bodyBytes": replay_int(request, "bodyBytes", 0),
    "routeId": replay_text(exchange, "routeId", ""),
    "mode": replay_text(exchange, "mode", "capture"),
    "tags": replay_strings(exchange, "tags").to_json(),
  }
}

///|
fn compare_exchange_desc(left : Json, right : Json) -> Int {
  let a = replay_int64(left, "sequence", 0L)
  let b = replay_int64(right, "sequence", 0L)
  if a > b {
    -1
  } else if a < b {
    1
  } else {
    0
  }
}

///|
fn filter_exchanges(input : Json) -> Json {
  let filter = replay_field(input, "filter")
  let offset = clamp_int(replay_int(input, "offset", 0), 0, 100000000)
  let limit = clamp_int(replay_int(input, "limit", 50), 1, 500)
  let matches = replay_array(input, "exchanges").filter(exchange => {
    exchange_matches_filter(exchange, filter)
  })
  matches.sort_by(compare_exchange_desc)
  let summaries : Array[Json] = []
  let end = (offset + limit).min(matches.length())
  if offset < matches.length() {
    for index = offset; index < end; index = index + 1 {
      summaries.push(exchange_summary(matches[index]))
    }
  }
  {
    "total": matches.length(),
    "offset": offset,
    "limit": limit,
    "hasMore": end < matches.length(),
    "items": summaries.to_json(),
  }
}

///|
pub fn filter_exchanges_json(source : String) -> String {
  replay_result(filter_exchanges(replay_parse(source, "history filter input"))) catch {
    error => replay_error(error.to_string())
  }
}
