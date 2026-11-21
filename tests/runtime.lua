local root = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/tests/")
package.path = assert(root) .. "/?.lua;" .. package.path
local common = require("common")
local endpoint = common.call("server.status").listeners[1].endpoint
assert(endpoint:match("^unix:///tmp/opencode/rex%-integration/"), "Use a private test server")
local projects = require("projects")
local created = {}
local state = os.getenv("XDG_STATE_HOME")
assert(
  state and state:match("^/tmp/opencode/rex%-integration/"),
  "Run with an isolated XDG_STATE_HOME"
)
local base = state .. "/projects"

local ok, err = pcall(function()
  common.exec({ "/bin/mkdir", "-p", base .. "/one/same name", base .. "/two/same name" })
  local layout = common.layout
  common.layout = function(cwd)
    return layout(cwd, { "/bin/cat" }, true)
  end
  local same = common.canonical(base .. "/one/same name")
  local manual = common.call("session.create", {
    label = "Manual runtime test",
    initial_windows = { { window_label = "Manual", layout = common.layout(same) } },
  })
  created[#created + 1] = manual.session_id
  common.call("session.attach", { session_id = manual.session_id })
  local pane = { session_id = manual.session_id, block_id = manual.initial_windows[1].block_ids[1] }
  local cwd
  for _ = 1, 30 do
    cwd = common.cwd(pane, false)
    if cwd == same then
      break
    end
    rex.sleep(0.05)
  end
  assert(cwd == same, "Manual session must start in the project directory")
  local first = projects.open({}, base .. "/one/same name")
  assert(first.session_id ~= manual.session_id, "Opening a project adopted a manual session")
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
  local tools = assert(loadfile(os.getenv("HOME") .. "/.local/share/rex/tools.lua"))()
  for name, path in pairs(tools) do
    local file = assert(io.open(path, "r"), "Missing tool: " .. name)
    file:close()
  end
  print("Rex runtime: manual isolation, canonical and renamed reuse, tabs, cwd and tools passed")
end)

for _, id in ipairs(created) do
  local attached = rex.call("session.attach", { session_id = id })
  if attached then
    rex.call("session.destroy", { session_id = id })
  end
end
assert(ok, err)
