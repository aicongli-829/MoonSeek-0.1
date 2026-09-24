///|
fn slash_path(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
fn parent_name(path : String) -> String {
  let clean = slash_path(path)
  match clean.rev_find("/") {
    Some(index) => clean[:index].to_owned()
    None => ""
  }
}

///|
async fn ensure_parent(path : String) -> Unit {
  let parent = parent_name(path)
  if parent != "" && !@fs.exists(parent) {
    @fs.mkdir(parent, recursive=true)
  }
}
