local root = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/tests/")
package.path = assert(root) .. "/?.lua;" .. package.path
local common = require("common")
local endpoint = common.call("server.status").listeners[1].endpoint
assert(endpoint:match("^unix:///tmp/opencode/rex%-integration/"), "Use a private test server")
local projects = require("projects")
local created = {}
local base = "/tmp/opencode/rex-integration/projects"
assert(
  (os.getenv("XDG_STATE_HOME") or ""):match("^/tmp/opencode/rex%-integration/"),
  "Run with an isolated XDG_STATE_HOME"
)

local ok, err = pcall(function()
  common.exec({ "/bin/mkdir", "-p", base .. "/one/same name", base .. "/two/same name" })
  local layout = common.layout
  common.layout = function(cwd)
    return layout(cwd, { "/bin/cat" }, true)
  end
  local first = projects.open({}, base .. "/one/same name")
  created[#created + 1] = first.session_id
  assert(projects.open({}, base .. "/one/./same name").session_id == first.session_id)
  common.call("session.attach", { session_id = first.session_id })
  common.call(
    "session.set_label",
    { session_id = first.session_id, label = "Renamed runtime test" }
  )
  assert(projects.open({}, base .. "/one/same name").session_id == first.session_id)
  local second = projects.open({}, base .. "/two/same name")
  created[#created + 1] = second.session_id
  assert(second.session_id ~= first.session_id)
  common.layout = layout

  common.call("session.attach", { session_id = first.session_id })
  local view = common.call("session.view", { session_id = first.session_id })
  assert(#view.windows == 2, "Project must contain two tabs")
  local window = view.windows[1]
  rex.sleep(0.3)
  local origin =
    common.origin({ session_id = first.session_id, block_id = window.focused_block_id })
  assert(
    origin.cwd == common.canonical(base .. "/one/same name"),
    assert(rex.json.encode({
      origin = origin,
      opened = first,
      process = common.terminal(origin, "process"),
    }))
  )
  common.call(
    "session.focus_window",
    { session_id = first.session_id, window_id = window.window_id }
  )
  local selected = common.popup(origin, function(file)
    return common.fzf(file, "alpha\nbeta\n", { "--filter=beta" })
  end)
  assert(selected == "beta\n", tostring(selected))
  local after = common.call("session.view", { session_id = first.session_id })
  assert(after.active_window_id == window.window_id)
  assert(#after.windows[1].layers == 1, "Completed popup left a floating layer")
  assert(after.windows[1].focused_block_id == origin.block_id, "Popup did not restore origin focus")

  assert(common.popup(origin, function(file)
    return common.fzf(file, "alpha\n", { "--filter=no-match" })
  end) == nil, "Cancelled picker returned output")
  after = common.call("session.view", { session_id = first.session_id })
  assert(#after.windows[1].layers == 1, "Cancelled popup left a floating layer")

  local captured = require("text").capture(origin, { origin.block_id })
  assert(type(captured) == "string")
  local tools = assert(loadfile(os.getenv("HOME") .. "/.local/share/rex/tools.lua"))()
  for name, path in pairs(tools) do
    local file = assert(io.open(path, "r"), "Missing tool: " .. name)
    file:close()
  end
  print(
    "Rex runtime: canonical project reuse, renamed sessions, two tabs, popup selection/cancel/focus/cleanup, capture and tools passed"
  )
end)

for _, id in ipairs(created) do
  local attached = rex.call("session.attach", { session_id = id })
  if attached then
    rex.call("session.destroy", { session_id = id })
  end
end
assert(ok, err)
