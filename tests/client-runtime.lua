local root = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/tests/")
package.path = assert(root) .. "/?.lua;" .. package.path
local common = require("common")
local original = assert(rex.args.return_session, "Pass return_session=ID to restore the app's view")
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
  print("Rex client: activated login shell without tmux autostart")
end)

local restored, restore_err = pcall(rex.client.queue, "session.select", { session_id = original })
common.call("session.attach", { session_id = id })
common.call("session.destroy", { session_id = id })
assert(restored, restore_err)
assert(ok, err)
