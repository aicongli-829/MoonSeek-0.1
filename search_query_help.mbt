///|
fn query_operator(
  syntax : String,
  description : String,
  examples : Array[String],
) -> Json {
  {
    "syntax": syntax,
    "description": description,
    "examples": examples.to_json(),
  }
}

///|
/// Machine-readable query documentation shared by the CLI, local web app and
/// future editor integrations. Keeping this next to the parser prevents help
/// text from drifting away from supported syntax.
pub fn search_query_help_json() -> String {
  (
    {
      "operators": [
        query_operator(
          "words",
          "Match filename, relative path, or indexed text content.",
          ["moonbit search", "meeting notes"],
        ),
        query_operator(
          "\"exact phrase\"",
          "Require the phrase terms and boost adjacent phrase matches.",
          ["\"quick start\"", "\"error code 404\""],
        ),
        query_operator(
          "-word",
          "Remove files containing a term from the result set.",
          ["report -draft", "moonbit -generated"],
        ),
        query_operator(
          "ext:extension",
          "Restrict results to one or more exact file extensions.",
          ["ext:md", "ext:mbt,md,json"],
        ),
        query_operator(
          "type:category",
          "Restrict results to a semantic file category.",
          ["type:image", "type:code,document"],
        ),
        query_operator("path:text", "Require text in the relative path.", [
          "path:docs", "path:src/core",
        ]),
        query_operator(
          "root:text",
          "Restrict results to an indexed root whose path contains text.",
          ["root:projects", "root:notes"],
        ),
        query_operator(
          "size:range",
          "Filter by bytes, a unit, a comparison, or a named size bucket.",
          ["size:<1mb", "size:10kb..2mb", "size:large"],
        ),
        query_operator(
          "modified:range",
          "Filter by the stored filesystem modification timestamp.",
          ["modified:100..500", "modified:>1720000000"],
        ),
      ].to_json(),
      "categories": [
        "document", "spreadsheet", "presentation", "image", "audio", "video", "archive",
        "code", "web", "data", "script", "executable", "font", "other",
      ].to_json(),
      "sizeBuckets": [
        { "name": "empty", "description": "exactly 0 bytes" },
        { "name": "tiny", "description": "up to 100 KiB" },
        { "name": "small", "description": "up to 1 MiB" },
        { "name": "medium", "description": "1 MiB through 100 MiB" },
        { "name": "large", "description": "100 MiB through 1 GiB" },
        { "name": "huge", "description": "1 GiB or larger" },
      ].to_json(),
      "notes": [
        "Keywords are case-insensitive.", "CJK text is indexed as characters and adjacent character pairs.",
        "Filename matches receive a larger ranking weight than content matches.",
        "Filename fuzzy matching handles prefixes, subsequences, and short typos.",
      ].to_json(),
    } : Json).stringify()
}
