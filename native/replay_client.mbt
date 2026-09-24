///|
fn request_method(value : String) -> @http.RequestMethod raise {
  match value.trim().to_owned().to_upper() {
    "GET" => Get
    "HEAD" => Head
    "POST" => Post
    "PUT" => Put
    "DELETE" => Delete
    "OPTIONS" => Options
    "TRACE" => Trace
    "PATCH" => Patch
    verb => fail("unsupported HTTP method " + verb)
  }
}

///|
fn split_absolute_url(url : String) -> (String, String) raise {
  guard url.find("://") is Some(scheme_end) else {
    fail("target URL must start with http:// or https://")
  }
  let scheme = url[:scheme_end].to_owned().to_lower()
  guard scheme == "http" || scheme == "https" else {
    fail("only HTTP and HTTPS targets are supported")
  }
  let rest = url[scheme_end + 3:].to_owned()
  guard rest != "" else { fail("target URL is missing a host") }
  match rest.find("/") {
    Some(index) =>
      (scheme + "://" + rest[:index].to_owned(), rest[index:].to_owned())
    None => (scheme + "://" + rest, "/")
  }
}

///|
fn outbound_headers(request : Json) -> @http.Headers {
  let headers : @http.Headers = Map([])
  for row in json_array(request, "headers") {
    let name = json_text(row, "name", "").trim().to_owned()
    if name != "" &&
      !["host", "content-length", "connection"].contains(name.to_lower()) {
      headers[@http.CaseInsensitiveString(name)] = json_text(row, "value", "")
    }
  }
  headers
}

///|
fn response_headers(response : @http.Response) -> Array[Json] {
  let rows : Array[Json] = []
  for name, value in response.headers {
    rows.push({ "name": name.to_string(), "value": value })
  }
  for cookie in response.cookies {
    rows.push({
      "name": "set-cookie",
      "value": cookie.name + "=" + cookie.value,
    })
  }
  rows
}

///|
pub async fn replay_request(request : Json, target_url? : String = "") -> Json {
  let target = if target_url == "" {
    json_text(request, "targetUrl", "")
  } else {
    target_url
  }
  guard target != "" else { fail("a replay target URL is required") }
  let (origin, path) = split_absolute_url(target)
  let client = @http.Client(origin)
  defer client.close()
  let headers = outbound_headers(request)
  let verb = request_method(json_text(request, "method", "GET"))
  client.request(verb, path, extra_headers=headers)
  let body = json_text(request, "body", "")
  if body != "" {
    client.write(body)
  }
  let started = @env.now()
  let response = client.end_request()
  let content = client.read_all().text()
  let finished = @env.now()
  {
    "status": response.code,
    "reason": response.reason,
    "headers": response_headers(response).to_json(),
    "body": content,
    "durationMs": (finished - started).to_string(),
    "targetUrl": target,
  }
}

///|
pub async fn replay_exchange_json(
  history_path : String,
  exchange_id : String,
  target_url : String,
) -> String {
  try {
    let loaded = parse_document(
      get_exchange_json(history_path, exchange_id),
      "exchange lookup",
    )
    match json_field(loaded, "error") {
      String(message) => fail(message)
      _ => ()
    }
    let exchange = json_field(loaded, "exchange")
    let actual = replay_request(json_field(exchange, "request"), target_url~)
    let expected = json_field(exchange, "response")
    let difference = parse_document(
      @core.diff_responses_json(
        ({ "expected": expected, "actual": actual, "options": {} } : Json).stringify(),
      ),
      "response difference",
    )
    (
      {
        "exchangeId": exchange_id,
        "targetUrl": target_url,
        "response": actual,
        "difference": difference,
      } : Json).stringify()
  } catch {
    error => json_error(error.to_string())
  }
}
