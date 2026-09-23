///|
async fn main {
  @native.run_search_cli(@env.args()) catch {
    error => println("Error: " + error.to_string())
  }
}
