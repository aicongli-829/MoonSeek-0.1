///|
async fn main {
  @native.run_cli(@env.args()) catch {
    error => println("Error: " + error.to_string())
  }
}
