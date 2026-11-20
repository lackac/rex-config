local root = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/tests/")
package.path = assert(root) .. "/?.lua;" .. package.path
local common = require("common")
local original = assert(rex.args.return_session, "Pass return_session=ID to restore the app's view")
local endpoint = common.call("server.status").listeners[1].endpoint
local folder = "/tmp/opencode/rex-integration/client-project"
common.exec({ "/bin/mkdir", "-p", folder })
folder = common.canonical(folder)
local label = "Rex integration check " .. common.timestamp
local made = common.call("session.create", {
  label = label,
  initial_windows = {
    { window_label = "Disposable shell", layout = common.layout(folder) },
  },
})
local id = made.session_id
local block = made.initial_windows[1].block_ids[1]
local ok, err = pcall(function()
  common.call("session.attach", { session_id = id })
  local process
  for _ = 1, 200 do
    process = common.terminal({ session_id = id, block_id = block }, "process")
    if process.foreground and process.foreground.name == "tmux" then
      error("New Rex shell automatically attached tmux")
    end
    if
      process.foreground
      and process.foreground.name == "zsh"
      and process.foreground.cwd == folder
    then
      break
    end
    rex.sleep(0.05)
  end
  assert(
    process.foreground and process.foreground.name == "zsh" and process.foreground.cwd == folder,
    "Rex login shell did not retain the project cwd"
  )
  local opened, open_err = rex.invoke("project_open", { path = folder })
  assert(opened, open_err)
  assert(opened.session_id == id, "Opening an existing project duplicated its session")

  common.exec({
    common.tool("rex"),
    "--autostart=false",
    "-S",
    endpoint,
    "-C",
    assert(rex.args.client),
    "do",
    "-s",
    id,
    "-b",
    block,
    "project_picker",
  })
  assert(rex.wait("block_created", nil, 10), "Project picker did not create a floating terminal")
  local view = common.call("session.view", { session_id = id })
  local popup = assert(view.windows[1].layers[2]).blocks[1].block_id
  for _ = 1, 200 do
    process = common.terminal({ session_id = id, block_id = popup }, "process")
    if process.foreground and process.foreground.name == "fzf" then
      break
    end
    rex.sleep(0.05)
  end
  assert(
    process.foreground and process.foreground.name == "fzf",
    "Project picker fzf did not start"
  )
  common.terminal({ session_id = id, block_id = popup }, "write", { data = label })
  common.exec({
    common.tool("rex"),
    "--autostart=false",
    "-S",
    endpoint,
    "send-key",
    "-s",
    id,
    "-b",
    popup,
    "enter",
  })
  assert(
    rex.wait("block_closed", { block_id = popup }, 10),
    "Selected project picker did not close"
  )
  view = common.call("session.view", { session_id = id })
  assert(#view.windows[1].layers == 1 and view.windows[1].focused_block_id == block)
  print(
    "Rex client: activated login shell, no tmux autostart, existing-project selection, floating picker and cleanup passed"
  )
end)

-- Preserve every unrelated registry entry; remove only this test's own mapping.
pcall(function()
  local state = (os.getenv("XDG_STATE_HOME") or os.getenv("HOME") .. "/.local/state")
    .. "/rex/projects.json"
  local temporary = common
    .exec({ "/usr/bin/mktemp", state .. "." .. common.timestamp .. ".XXXXXX" })
    :gsub("\n$", "")
  local text = common.read(state)
  if text then
    local entries = assert(rex.json.decode(text))
    if entries[folder] == id then
      entries[folder] = nil
      common.write(temporary, assert(rex.json.encode(entries)))
      assert(os.rename(temporary, state))
    end
  end
  os.remove(temporary)
end)
local restored, restore_err = pcall(rex.client.queue, "session.select", { session_id = original })
common.call("session.attach", { session_id = id })
common.call("session.destroy", { session_id = id })
assert(restored, restore_err)
assert(ok, err)
