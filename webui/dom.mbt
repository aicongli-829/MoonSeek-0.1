///|
/// The JavaScript FFI in this file is intentionally narrow: it only exposes
/// browser primitives. Application state, validation and rendering stay in MoonBit.
extern "js" fn dom_value(id : String) -> String =
  #|(id) => {
  #|  const node = document.getElementById(id);
  #|  return node && "value" in node ? String(node.value) : "";
  #|}

///|
extern "js" fn dom_set_value(id : String, value : String) -> Unit =
  #|(id, value) => { const node = document.getElementById(id); if (node) node.value = value; }

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
  #|  fetch(path, { method: path === "/api/session" ? "GET" : "POST", headers: { "Content-Type": "application/json", "X-MoonSeek-Token": globalThis.__moonseekToken || "" }, body: path === "/api/session" ? undefined : body })
  #|    .then(async response => callback(await response.text()))
  #|    .catch(error => callback(JSON.stringify({ error: error.message })));
  #|}

///|
extern "js" fn set_api_token(token : String) -> Unit =
  #|(token) => { globalThis.__moonseekToken = token; }

///|
extern "js" fn bind_search_input(id : String, callback : () -> Unit) -> Unit =
  #|(id, callback) => {
  #|  const node = document.getElementById(id);
  #|  if (!node) return;
  #|  let timer = 0;
  #|  node.addEventListener("input", () => {
  #|    clearTimeout(timer);
  #|    timer = setTimeout(() => callback(), 90);
  #|  });
  #|}

///|
extern "js" fn bind_global_shortcuts(search_id : String) -> Unit =
  #|(searchId) => {
  #|  window.addEventListener("keydown", event => {
  #|    if ((event.ctrlKey && event.key.toLowerCase() === "k") || (event.key === "/" && document.activeElement?.tagName !== "INPUT")) {
  #|      event.preventDefault();
  #|      const node = document.getElementById(searchId);
  #|      node?.focus();
  #|      node?.select();
  #|    }
  #|  });
  #|}

///|
extern "js" fn dom_focus(id : String) -> Unit =
  #|(id) => document.getElementById(id)?.focus()

///|
extern "js" fn copy_text(value : String) -> Unit =
  #|(value) => navigator.clipboard?.writeText(value)

///|
extern "js" fn browser_confirm(message : String) -> Bool =
  #|(message) => window.confirm(message)
