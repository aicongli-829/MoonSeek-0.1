///|
async fn main {
  @native.run_cli(@env.args()) catch {
    error => println("错误：" + error.to_string())
  }
}
