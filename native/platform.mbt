///|
/// Read UTF-8 text using MoonBit's native asynchronous filesystem.
pub async fn read_text(path : String) -> String {
  @fs.read_file(path).text()
}
