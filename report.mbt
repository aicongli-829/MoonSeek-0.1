///| Decode rows at the untrusted JavaScript boundary. Missing optional fields
/// become empty text, while source and target are checked by the caller.
fn decode_report_rows(value : Json) -> Array[PlanRow] {
  array_field(value, "rows").map(row => {
    source: text_field(row, "source", ""),
    target: text_field(row, "target", ""),
    status: text_field(row, "status", ""),
    reason: text_field(row, "reason", ""),
    category: text_field(row, "category", ""),
  })
}

///| A report never accepts paths that contain control characters. This avoids
/// producing ambiguous multi-line records even if a caller bypasses planning.
fn report_row_error(row : PlanRow) -> String? {
  if row.source == "" || row.target == "" {
    return Some("报告路径不能为空")
  }
  for value in [row.source, row.target, row.status, row.reason, row.category] {
    for character in value.iter() {
      if character == '\u{0000}' {
        return Some("报告内容不能包含空字符")
      }
    }
  }
  None
}

///| Spreadsheet applications interpret a few leading characters as formulas.
/// Prefixing an apostrophe preserves the value as data when a CSV is opened.
fn spreadsheet_safe(value : String) -> String {
  if value.length() == 0 {
    return value
  }
  let first = value[0]
  if first == 61 || first == 43 || first == 45 || first == 64 || first == 9 || first == 13 {
    "'" + value
  } else {
    value
  }
}

///| RFC-4180 style quoting. Quoting every field keeps output deterministic and
/// handles commas, quotes, CRLF and Unicode without branching on content.
pub fn csv_cell(value : String) -> String {
  let safe = spreadsheet_safe(value)
  "\"" + safe.replace_all(old="\"", new="\"\"") + "\""
}

///| Generate a UTF-8 CSV with BOM for common Windows spreadsheet programs.
pub fn report_csv(rows : Array[PlanRow]) -> String {
  let output = StringBuilder()
  output.write_string("\u{FEFF}")
  output.write_string("原路径,目标路径,状态,说明,分类\r\n")
  for index, row in rows {
    output.write_string(csv_cell(row.source))
    output.write_char(',')
    output.write_string(csv_cell(row.target))
    output.write_char(',')
    output.write_string(csv_cell(row.status))
    output.write_char(',')
    output.write_string(csv_cell(row.reason))
    output.write_char(',')
    output.write_string(csv_cell(row.category))
    if index + 1 < rows.length() {
      output.write_string("\r\n")
    }
  }
  output.to_string()
}

///| Escape the small set of characters that can change a Markdown table.
pub fn markdown_cell(value : String) -> String {
  value
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="|", new="\\|")
  .replace_all(old="\r", new=" ")
  .replace_all(old="\n", new=" ")
  .trim()
  .to_owned()
}

///| Human-readable preview suitable for issues, pull requests and submissions.
pub fn report_markdown(created : String, rows : Array[PlanRow]) -> String {
  let output = StringBuilder()
  output.write_string("# FileNest 整理预览\n\n")
  output.write_string("生成时间：" + created + "\n\n")
  output.write_string("| 原路径 | 目标路径 | 状态 | 说明 | 分类 |\n")
  output.write_string("| --- | --- | --- | --- | --- |\n")
  for row in rows {
    output.write_string("| " + markdown_cell(row.source))
    output.write_string(" | " + markdown_cell(row.target))
    output.write_string(" | " + markdown_cell(row.status))
    output.write_string(" | " + markdown_cell(row.reason))
    output.write_string(" | " + markdown_cell(row.category) + " |\n")
  }
  output.write_string("\n这是预览报告，实际执行会再次检查文件状态。")
  output.to_string()
}

///| Machine-readable report kept intentionally stable for scripts.
pub fn report_machine_json(created : String, rows : Array[PlanRow]) -> String {
  ({
    "schemaVersion": 1,
    "created": created,
    "rows": rows.to_json(),
  } : Json).stringify()
}

///| Preserve the complete approved preview in JSON exports. The extra schema
/// version lets future readers distinguish compatible report revisions.
pub fn report_plan_machine_json(plan : Json, created : String, rows : Array[PlanRow]) -> String {
  ({
    "schemaVersion": 1,
    "id": field(plan, "id"),
    "created": created,
    "rows": rows.to_json(),
    "options": field(plan, "options"),
    "summary": field(plan, "summary"),
  } : Json).stringify()
}

///| Single JS-facing report boundary. It returns an envelope so MoonBit errors
/// cannot be confused with valid report text.
pub fn report_json(input : String) -> String {
  let document = @json.parse(input) catch {
    _ => return ({ "error": "报告输入不是合法 JSON" } : Json).stringify()
  }
  let format = text_field(document, "format", "")
  let nested = field(document, "plan")
  let plan = if nested is Object(_) { nested } else { document }
  let created = text_field(plan, "created", "")
  let rows = decode_report_rows(plan)
  if rows.length() > 10000 {
    return ({ "error": "报告最多包含 10,000 行" } : Json).stringify()
  }
  for row in rows {
    if report_row_error(row) is Some(error) {
      return ({ "error": error } : Json).stringify()
    }
  }
  let content = match format {
    "csv" => report_csv(rows)
    "md" => report_markdown(created, rows)
    "json" => report_plan_machine_json(plan, created, rows)
    _ => return ({ "error": "不支持的报告格式" } : Json).stringify()
  }
  ({ "content": content } : Json).stringify()
}
