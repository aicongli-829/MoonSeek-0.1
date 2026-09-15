///|
fn main {
  initialize_events()
  render_rules()
  render_categories()
  api_request("/api/session", "{}", source => {
    response(source, session => {
      set_api_token(ui_text(session, "token", ""))
      state.built_in_templates = ui_array(session, "builtInTemplates")
      render_templates()
      let initial = ui_text(session, "initialRoot", "")
      if initial != "" {
        dom_set_value("root", initial)
      }
    })
  })
}
