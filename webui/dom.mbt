///|
/// The JavaScript FFI in this file is intentionally narrow: it only exposes
/// browser primitives. Application state, validation and rendering stay in MoonBit.
extern "js" fn dom_value(id : String) -> String =
  #|(id) => {
  #|  const node = document.getElementById(id);
  #|  return node && "value" in node ? String(node.value) : "";
  #|}

///|
extern "js" fn dom_checked(id : String) -> Bool =
  #|(id) => Boolean(document.getElementById(id)?.checked)

///|
extern "js" fn dom_set_value(id : String, value : String) -> Unit =
  #|(id, value) => { const node = document.getElementById(id); if (node) node.value = value; }

///|
extern "js" fn dom_set_checked_value(id : String, value : Bool) -> Unit =
  #|(id, value) => { const node = document.getElementById(id); if (node) node.checked = value; }

///|
extern "js" fn dom_text(id : String, value : String) -> Unit =
  #|(id, value) => { const node = document.getElementById(id); if (node) node.textContent = value; }

///|
extern "js" fn dom_html(id : String, value : String) -> Unit =
  #|(id, value) => { const node = document.getElementById(id); if (node) node.innerHTML = value; }

///|
extern "js" fn dom_hidden(id : String, hidden : Bool) -> Unit =
  #|(id, hidden) => { const node = document.getElementById(id); if (node) node.hidden = hidden; }

///|
extern "js" fn dom_disabled(id : String, disabled : Bool) -> Unit =
  #|(id, disabled) => { const node = document.getElementById(id); if (node) node.disabled = disabled; }

///|
extern "js" fn dom_class_toggle(
  id : String,
  name : String,
  active : Bool,
) -> Unit =
  #|(id, name, active) => document.getElementById(id)?.classList.toggle(name, active)

///|
extern "js" fn bind_click(id : String, callback : () -> Unit) -> Unit =
  #|(id, callback) => document.getElementById(id)?.addEventListener("click", () => callback())

///|
extern "js" fn bind_change(id : String, callback : () -> Unit) -> Unit =
  #|(id, callback) => document.getElementById(id)?.addEventListener("change", () => callback())

///|
extern "js" fn bind_delegate(
  id : String,
  callback : (String, String, String) -> Unit,
) -> Unit =
  #|(id, callback) => {
  #|  const root = document.getElementById(id);
  #|  if (!root) return;
  #|  const send = (event) => {
  #|    const node = event.target.closest("[data-action]");
  #|    if (node && root.contains(node)) callback(node.dataset.action || "", node.dataset.index || "", "value" in node ? String(node.value) : "");
  #|  };
  #|  root.addEventListener("click", send);
  #|  root.addEventListener("change", send);
  #|  root.addEventListener("input", send);
  #|}

///|
extern "js" fn api_request(
  path : String,
  body : String,
  callback : (String) -> Unit,
) -> Unit =
  #|(path, body, callback) => {
  #|  fetch(path, { method: path === "/api/session" ? "GET" : "POST", headers: { "Content-Type": "application/json", "X-FileNest-Token": globalThis.__filenestToken || "" }, body: path === "/api/session" ? undefined : body })
  #|    .then(async response => callback(await response.text()))
  #|    .catch(error => callback(JSON.stringify({ error: error.message })));
  #|}

///|
extern "js" fn set_api_token(token : String) -> Unit =
  #|(token) => { globalThis.__filenestToken = token; }

///|
extern "js" fn save_download(content : String, name : String) -> Unit =
  #|(content, name) => {
  #|  const url = URL.createObjectURL(new Blob([content], { type: "text/plain;charset=utf-8" }));
  #|  const link = Object.assign(document.createElement("a"), { href: url, download: name });
  #|  link.click();
  #|  setTimeout(() => URL.revokeObjectURL(url), 1000);
  #|}

///|
extern "js" fn browser_confirm(message : String) -> Bool =
  #|(message) => window.confirm(message)

///|
extern "js" fn browser_prompt(message : String) -> String =
  #|(message) => window.prompt(message) || ""
