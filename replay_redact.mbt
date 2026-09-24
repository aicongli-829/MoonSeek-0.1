///|
let default_sensitive_headers : Array[String] = [
  "authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key", "api-key",
  "x-auth-token",
]

///|
let default_sensitive_fields : Array[String] = [
  "password", "passwd", "secret", "token", "access_token", "refresh_token", "api_key",
  "apikey", "client_secret", "credit_card", "card_number", "cvv",
]

///|
fn mask_secret(value : String, replacement : String) -> String {
  if value == "" {
    value
  } else if replacement != "" {
    replacement
  } else {
    "[REDACTED]"
  }
}

///|
fn redaction_names(
  policy : Json,
  key : String,
  defaults : Array[String],
) -> Array[String] {
  let configured = replay_strings(policy, key).map(lowercase)
  let result = defaults.copy()
  for name in configured {
    if !result.contains(name) {
      result.push(name)
    }
  }
  result
}

///|
fn redact_headers(rows : Array[Json], policy : Json) -> Array[Json] {
  let names = redaction_names(policy, "headers", default_sensitive_headers)
  let replacement = replay_text(policy, "replacement", "[REDACTED]")
  rows.map(row => {
    let name = replay_text(row, "name", "")
    let value = replay_text(row, "value", "")
    {
      "name": name,
      "value": if names.contains(lowercase(name)) {
        mask_secret(value, replacement)
      } else {
        value
      },
    }
  })
}

///|
fn redact_query(rows : Array[Json], policy : Json) -> Array[Json] {
  let defaults : Array[String] = [
    "token", "access_token", "api_key", "apikey", "key", "signature", "sig",
  ]
  let names = redaction_names(policy, "query", defaults)
  let replacement = replay_text(policy, "replacement", "[REDACTED]")
  rows.map(row => {
    let name = replay_text(row, "name", "")
    let value = replay_text(row, "value", "")
    {
      "name": name,
      "value": if names.contains(lowercase(name)) {
        mask_secret(value, replacement)
      } else {
        value
      },
    }
  })
}

///|
fn redact_json_value(
  value : Json,
  sensitive : Array[String],
  replacement : String,
  depth : Int,
) -> Json {
  if depth > 64 {
    return Json::string("[DEPTH-LIMIT]")
  }
  match value {
    Object(fields) => {
      let output : Map[String, Json] = Map([])
      for key, child in fields {
        output[key] = if sensitive.contains(lowercase(key)) {
          Json::string(mask_secret(json_scalar_text(child), replacement))
        } else {
          redact_json_value(child, sensitive, replacement, depth + 1)
        }
      }
      Json::object(output)
    }
    Array(items) =>
      items
      .map(item => redact_json_value(item, sensitive, replacement, depth + 1))
      .to_json()
    _ => value
  }
}

///|
fn redact_body(body : String, content_type : String, policy : Json) -> String {
  if body == "" {
    return body
  }
  let sensitive = redaction_names(
    policy, "jsonFields", default_sensitive_fields,
  )
  let replacement = replay_text(policy, "replacement", "[REDACTED]")
  if lowercase(content_type).contains("json") ||
    body.trim().has_prefix("{") ||
    body.trim().has_prefix("[") {
    match try_parse_json(body) {
      Some(parsed) =>
        redact_json_value(parsed, sensitive, replacement, 0).stringify()
      None => body
    }
  } else if lowercase(content_type).contains("x-www-form-urlencoded") {
    parse_query(body)
    .map(row => {
      let name = replay_text(row, "name", "")
      let value = replay_text(row, "value", "")
      let rendered = if sensitive.contains(lowercase(name)) {
        mask_secret(value, replacement)
      } else {
        value
      }
      name + "=" + rendered
    })
    .join("&")
  } else {
    body
  }
}

///|
fn redact_message(message : Json, policy : Json) -> Json {
  let normalized = normalize_request(message)
  let headers = redact_headers(replay_array(normalized, "headers"), policy)
  let content_type = header_value(normalized, "content-type").unwrap_or("")
  {
    "id": replay_text(normalized, "id", ""),
    "receivedAt": replay_text(normalized, "receivedAt", ""),
    "method": replay_text(normalized, "method", ""),
    "target": replay_text(normalized, "target", ""),
    "path": replay_text(normalized, "path", ""),
    "query": redact_query(replay_array(normalized, "query"), policy).to_json(),
    "headers": headers.to_json(),
    "body": redact_body(
      replay_text(normalized, "body", ""),
      content_type,
      policy,
    ),
    "remoteAddress": replay_text(normalized, "remoteAddress", ""),
  }
}

///|
fn redact_response(response : Json, policy : Json) -> Json {
  let headers = redact_headers(replay_array(response, "headers"), policy)
  let content_type = rows_to_string_map(headers, normalize_names=true)
    .get("content-type")
    .unwrap_or("")
  {
    "status": replay_int(response, "status", 200),
    "headers": headers.to_json(),
    "body": redact_body(replay_text(response, "body", ""), content_type, policy),
    "durationMs": replay_int64(response, "durationMs", 0L).to_string(),
  }
}

///|
pub fn redact_exchange_json(source : String) -> String {
  try {
    let input = replay_parse(source, "redaction input")
    let policy = replay_field(input, "policy")
    replay_result({
      "request": redact_message(replay_field(input, "request"), policy),
      "response": redact_response(replay_field(input, "response"), policy),
    })
  } catch {
    error => replay_error(error.to_string())
  }
}
