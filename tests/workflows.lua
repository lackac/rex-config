-- Run from the repository root: luajit tests/workflows.lua
-- Or: nvim --headless -u NONE -l tests/workflows.lua
package.path = "./?.lua;" .. package.path

local actions, calls, commands, queued, json = {}, {}, {}, {}, {}
local handlers = {}
local logs, zoxide = {}, nil
local canonical_aliases = { ["/links/alias"] = "/linked/project" }
local function equal(actual, expected)
  assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function fails(fn, pattern)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(pattern), tostring(err))
end
rex = {
  action = function(action)
    actions[action.name] = action
  end,
  call = function(method, args)
    calls[#calls + 1] = { method = method, args = args }
    assert(handlers[method], "Unexpected API: " .. method)
    return handlers[method](args)
  end,
  exec = function(argv, opts)
    commands[#commands + 1] = { argv = argv, opts = opts }
    local stdout = ""
    if argv[1] == "/usr/bin/mktemp" then
      stdout = argv[2]:gsub("XXXXXX$", "mock") .. "\n"
    elseif argv[1] == "/tools/zsh" and argv[3] == "-c" and argv[4]:find("pwd %-P") then
      local path = argv[6]
      if path == "/missing" then
        return { ok = false, stderr = "Directory not found" }
      end
      stdout = (canonical_aliases[path] or path:gsub("/alias$", "/project")) .. "\n"
    elseif argv[1] == "/tools/zoxide" then
      return zoxide
    end
    return { ok = true, code = 0, stdout = stdout, stderr = "" }
  end,
  json = {
    encode = function(data)
      json[#json + 1] = data
      return "json:" .. #json
    end,
    decode = function(data)
      return json[tonumber(data:match("^json:(%d+)$"))]
    end,
  },
  layout = {
    block = function(layout)
      return { block = layout }
    end,
  },
  client = {
    queue = function(name, args)
      queued[#queued + 1] = { name = name, args = args }
    end,
  },
  log = function(level, message)
    logs[#logs + 1] = { level = level, message = message }
  end,
  ui = {
    pick = function()
      return nil, "cancelled"
    end,
  },
}

local common = require("common")
local projects = require("projects")
require("popups").setup()
require("sessions").setup()
projects.setup()
equal(#calls, 0)
equal(#commands, 0)
for _, name in ipairs({
  "project_open",
  "project_open_opencode",
  "project_picker",
  "popup_lazygit",
  "session_close",
}) do
  assert(actions[name], "Missing " .. name)
end

common.tool = function(name)
  return "/tools/" .. name
end
equal(common.canonical("/a directory/alias"), "/a directory/project")
equal(commands[#commands].argv[6], "/a directory/alias")
fails(function()
  common.canonical("/x\ny")
end, "Invalid path")
equal(projects.name(os.getenv("HOME")), "main")
equal(projects.name("/some/example-project"), "example-project")

local function block(id)
  return { block_id = id, creator_name = common.creator }
end
local window = {
  window_id = "window:origin",
  focused_block_id = "block:origin",
  layers = {
    { blocks = { block("block:origin"), block("block:split") } },
    { blocks = { block("block:floating") } },
  },
}
local view = {
  active_window_id = window.window_id,
  windows = {
    window,
    {
      window_id = "window:other",
      focused_block_id = "block:other",
      layers = { { blocks = { block("block:other") } } },
    },
  },
  label = "renamed",
}
handlers["session.view"] = function()
  return view
end
handlers["session.attach"] = function()
  return { view = view }
end
handlers[common.creator .. ".process"] = function()
  return { foreground = { cwd = "/origin dir" } }
end
local origin = common.origin({ session_id = "session:full-origin" })
equal(origin.window_id, "window:origin")
equal(origin.block_id, "block:origin")
equal(origin.cwd, "/origin dir")
local explicit = common.origin({ session_id = origin.session_id, block_id = "block:other" })
equal(explicit.window_id, "window:other")

-- Lazygit opens in the originating tab and lets Rex manage its lifetime.
local layer = { layer_id = "layer:lazygit", block_ids = { "block:lazygit" } }
handlers["session.new_layer"] = function(args)
  equal(args.session_id, explicit.session_id)
  equal(args.window_id, explicit.window_id)
  equal(table.concat(args.bounds, ","), "0.1,0.1,0.8,0.8")
  equal(args.focus, true)
  local options = args.layout.block.options
  equal(options.cwd, explicit.cwd)
  equal(options.exit, nil)
  equal(
    table.concat(options.command, "\n"),
    '/tools/zsh\n-lic\nexec "$1"\nrex-lazygit\n/tools/lazygit'
  )
  return layer
end
local calls_before = #calls
equal(
  actions.popup_lazygit.run({ session_id = explicit.session_id, block_id = explicit.block_id }),
  layer
)
equal(#calls - calls_before, 3) -- Read the origin and cwd, then create the layer.

-- A manual session at the requested cwd cannot replace a stale saved ID.
local sessions = {
  { session_id = "session:full-a", label = "manual project" },
  { session_id = "session:full-b", label = "project" },
}
handlers[common.creator .. ".process"] = function(args)
  equal(args.session_id, "session:full-a")
  return { foreground = { cwd = "/new/project" } }
end
local state = (os.getenv("XDG_STATE_HOME") or os.getenv("HOME") .. "/.local/state")
  .. "/rex/projects.json"
local memory = {
  [state] = rex.json.encode({
    ["/new/project"] = "session:stale",
    ["/other/project"] = "session:full-b",
  }),
}
local real_rename = os.rename
os.rename = function(from, to)
  memory[to] = memory[from]
  memory[from] = nil
  return true
end
common.read = function(path)
  return memory[path]
end
common.write = function(path, value)
  memory[path] = value
end
local creates = 0
handlers["session.list"] = function()
  return { sessions = sessions }
end
handlers["session.create"] = function(args)
  creates = creates + 1
  equal(args.label, "project — /new/project")
  equal(#args.initial_windows, 2)
  equal(args.initial_windows[1].layout.block.options.cwd, "/new/project")
  local command = args.initial_windows[1].layout.block.options.command
  equal(command[1], "/tools/zsh")
  assert(command[3]:find('exec "%$2" %-il'))
  sessions[#sessions + 1] = { session_id = "session:created", label = args.label }
  return {
    session_id = "session:created",
    initial_windows = { { window_id = "window:opencode" }, { window_id = "window:shell" } },
  }
end
handlers["session.focus_window"] = function(args)
  equal(args.window_id, "window:opencode")
  return {}
end
calls_before = #calls
local opened = projects.open({ client_id = "client:origin" }, "/new/alias")
equal(opened.session_id, "session:created")
equal(#calls, calls_before + 4)
equal(opened.path, "/new/project")
equal(opened.started, nil)
equal(opened.window_id, nil)
equal(opened.block_id, nil)
equal(calls[calls_before + 1].method, "session.list")
equal(calls[calls_before + 2].method, "session.create")
equal(calls[calls_before + 3].method, "session.attach")
equal(calls[calls_before + 3].args.session_id, opened.session_id)
equal(calls[calls_before + 4].method, "session.focus_window")
local saved = rex.json.decode(memory[state])
equal(saved["/new/project"], "session:created")
equal(saved["/other/project"], "session:full-b")
calls_before = #calls
equal(projects.open({}, "/new/project").session_id, "session:created")
equal(#calls, calls_before + 1)
equal(calls[#calls].method, "session.list")
equal(creates, 1)
equal(queued[#queued].args.session_id, "session:created")
local queued_before = #queued
projects.open({ client_id = "client:cli" }, "/new/project")
equal(#queued, queued_before + 1)
equal(queued[#queued].args.session_id, "session:created")
handlers["session.list"] = function()
  return { sessions = {} }
end
handlers["session.create"] = function(args)
  equal(#args.initial_windows, 1)
  equal(args.label, "main")
  return { session_id = "session:main", initial_windows = { { window_id = "window:opencode" } } }
end
projects.open({}, os.getenv("HOME"))

-- The named action lists without a terminal and canonicalizes only on selection.
local default_pick = rex.ui.pick
local pick_project = actions.project_picker.run
sessions[3].label = "renamed project"
handlers["session.list"] = function()
  return { sessions = { sessions[3], sessions[1] } }
end
zoxide = {
  ok = true,
  stdout = "/new//./project/\n"
    .. "/z/another project\n"
    .. "/new/alias\n"
    .. "/a/nix-config\n"
    .. "/z/another project/\n"
    .. os.getenv("HOME")
    .. "\n",
}
local function check_picker(opts)
  equal(#opts.items, 6)
  equal(opts.items[1].title, "renamed project")
  equal(opts.items[1].subtitle, "/new/project")
  equal(opts.items[1].detail, "Session")
  equal(opts.items[2].title, "manual project")
  equal(opts.items[2].subtitle, nil)
  equal(opts.items[3].subtitle, "/z/another project")
  equal(opts.items[4].subtitle, "/new/alias")
  equal(opts.items[5].title, "nix-config")
  equal(opts.items[6].title, "main")
end
rex.ui.pick = function(opts)
  check_picker(opts)
  return opts.items[1].id
end
local commands_before = #commands
calls_before = #calls
local picker_ctx = { client_id = "client:origin" }
equal(pick_project(picker_ctx).session_id, "session:created")
equal(queued[#queued].name, "session.select")
equal(queued[#queued].args.session_id, "session:created")
equal(#calls, calls_before + 1)
equal(calls[#calls].method, "session.list")
equal(#commands, commands_before + 1)
equal(table.concat(commands[#commands].argv, " "), "/tools/zoxide query --list")
equal(commands[#commands].opts.cwd, nil)

rex.ui.pick = function(opts)
  check_picker(opts)
  return opts.items[2].id
end
calls_before = #calls
equal(pick_project(picker_ctx).session_id, "session:full-a")
equal(queued[#queued].args.session_id, "session:full-a")
equal(#calls, calls_before + 1)
equal(calls[#calls].method, "session.list")

rex.ui.pick = function(opts)
  check_picker(opts)
  return opts.items[4].id
end
local reused = pick_project(picker_ctx)
equal(reused.session_id, "session:created")
equal(reused.path, "/new/project")
equal(queued[#queued].args.session_id, "session:created")

-- Missing or failed zoxide and prompt errors leave sessions usable and do not
-- create or select anything unless the picker returns a known ID.
local queued_after, logged = #queued, #logs
zoxide = nil
rex.ui.pick = function(opts)
  equal(#opts.items, 2)
  equal(opts.items[1].title, "renamed project")
  return nil, "cancelled"
end
equal(pick_project({}), nil)
equal(#logs, logged)
zoxide = { ok = false, stdout = "/ignored\n" }
rex.ui.pick = function(opts)
  equal(#opts.items, 2)
  return nil, "failed", "no prompt"
end
equal(pick_project({}), nil)
equal(logs[#logs].level, "warn")
equal(logs[#logs].message, "Project picker: failed: no prompt")
rex.ui.pick = function()
  return "not-an-item"
end
fails(function()
  pick_project({})
end, "Invalid project selection")
equal(#queued, queued_after)

local many = {}
for i = 1, 2000 do
  many[i] = "/dir-" .. i
end
zoxide = { ok = true, stdout = table.concat(many, "\n") }
rex.ui.pick = function(opts)
  equal(#opts.items, 2000)
  equal(opts.items[1].detail, "Session")
  equal(opts.items[2].detail, "Session")
  equal(opts.items[3].subtitle, "/dir-1")
  equal(opts.items[2000].subtitle, "/dir-1998")
  return nil, "cancelled"
end
equal(pick_project({}), nil)
rex.ui.pick = default_pick

-- Close uses the original ID even if focus changes while the question is open;
-- cancellation/unsupported UI never closes anything. Confirmation is required.
local destroys = 0
handlers["session.destroy"] = function(args)
  equal(args.session_id, origin.session_id)
  destroys = destroys + 1
  return {}
end
actions.session_close.run({ session_id = origin.session_id })
equal(destroys, 0)
rex.ui.pick = function()
  return nil, "unsupported"
end
actions.session_close.run({ session_id = origin.session_id })
equal(destroys, 0)
rex.ui.pick = function()
  view.active_window_id = "window:other"
  return "close"
end
actions.session_close.run({ session_id = origin.session_id })
equal(destroys, 1)

-- OpenCode links have a separate return contract and leave focus to the caller.
local link = actions.project_open_opencode
equal(table.concat(link.args.required, ","), "path,directory,conversation")
for _, arg in ipairs({ "path", "directory", "conversation" }) do
  equal(link.args.properties[arg].type, "string")
end
equal(link.args.properties.conversation.pattern, "^ses_[A-Za-z0-9]+$")
local directory = "/linked/project/a 'quoted'; directory"
canonical_aliases["/links/location"] = directory
local function open_link(path, location, conversation)
  return link.run(
    { client_id = "client:cli", session_id = "session:manual" },
    { path = path, directory = location, conversation = conversation or "ses_aB12" }
  )
end
local function check_target(target, window_id, block_id, started)
  equal(target.session_id, "session:linked")
  equal(target.window_id, window_id)
  equal(target.block_id, block_id)
  equal(target.started, started)
  equal(target.path, nil)
end
local function check_launch(tab, cwd)
  equal(tab.window_label, "OpenCode")
  local options = tab.layout.block.options
  equal(options.cwd, cwd)
  equal(options.login, false)
  equal(options.shell, "none")
  equal(options.command[1], "/tools/zsh")
  equal(options.command[5], "/tools/direnv")
  equal(#options.command, 6)
  assert(not table.concat(options.command, "\n"):find("ses_aB12", 1, true))
end
calls_before = #calls
for _, invalid in ipairs({ "ses_", "ses_x-y", "ses_x\n", "ses_x; date" }) do
  fails(function()
    open_link("/links/alias", "/links/location", invalid)
  end, "Invalid OpenCode conversation ID")
end
for _, outside in ipairs({ "/linked", "/linked/project-other" }) do
  fails(function()
    open_link("/links/alias", outside)
  end, "inside the project")
end
fails(function()
  open_link("/links/alias", "/missing")
end, "Directory not found")
fails(function()
  open_link("linked/project", "/links/location")
end, "must be absolute")
fails(function()
  open_link("/links/alias", nil)
end, "Missing OpenCode directory")
fails(function()
  open_link(nil, "/links/location")
end, "Invalid path")
equal(#calls, calls_before)

sessions = { { session_id = "session:manual", label = "project" } }
handlers["session.list"] = function()
  return { sessions = sessions }
end
local expected_root, expected_directory = "/linked/project", directory
handlers["session.create"] = function(args)
  equal(#args.initial_windows, 2)
  check_launch(args.initial_windows[1], expected_directory)
  equal(args.initial_windows[2].window_label, "Shell")
  equal(args.initial_windows[2].layout.block.options.cwd, expected_root)
  equal(args.initial_windows[2].layout.block.options.command[2], "-il")
  sessions[#sessions + 1] = { session_id = "session:linked", label = args.label }
  return {
    session_id = "session:linked",
    initial_windows = { { window_id = "window:first", block_ids = { "block:first" } } },
  }
end
queued_before = #queued
check_target(open_link("/links/alias", "/links/location"), "window:first", "block:first", true)
equal(#calls, calls_before + 2)
equal(#queued, queued_before)
equal(rex.json.decode(memory[state])["/linked/project"], "session:linked")
equal(sessions[2].label, "project — /linked/project")

local processes = {
  alternate = { foreground = { argv0 = "/bin/opencode", cwd = "/links/location" } },
  background = { child = { argv0 = "opencode", cwd = directory }, foreground = { name = "zsh" } },
  unrelated = { foreground = { argv0 = "opencode-helper", cwd = directory } },
  different = { foreground = { argv0 = "/bin/opencode", cwd = "/linked/project" } },
  missing = { foreground = { argv0 = "opencode", cwd = "/missing" } },
  wrapped = { foreground = { name = ".opencode2-wrapped", cwd = directory } },
}
local panes = {
  { block_id = "not-terminal", creator_name = "example", host_id = "host:local" },
  { block_id = "not-local", creator_name = common.creator, host_id = "host:remote" },
}
for _, key in ipairs({
  "background",
  "unrelated",
  "different",
  "missing",
  "vanished",
  "alternate",
  "wrapped",
}) do
  local pane = block(key)
  pane.host_id = "host:local"
  panes[#panes + 1] = pane
end
handlers["server.status"] = function()
  return { host_id = "host:local" }
end
handlers["session.attach"] = function(args)
  equal(args.session_id, "session:linked")
  return {
    view = { windows = { { window_id = "window:existing", layers = { { blocks = panes } } } } },
  }
end
handlers[common.creator .. ".process"] = function(args)
  equal(args.session_id, "session:linked")
  assert(args.block_id ~= "not-terminal" and args.block_id ~= "not-local")
  return processes[args.block_id]
end
local screen = { alternate = "primary", wrapped = "alternate" }
handlers[common.creator .. ".modes"] = function(args)
  equal(args.session_id, "session:linked")
  return { screen = assert(screen[args.block_id]) }
end
handlers["session.focus_window"] = nil
check_target(open_link("/links/alias", directory), "window:existing", "wrapped", false)
screen.alternate = "alternate"
check_target(open_link("/links/alias", directory), "window:existing", "alternate", false)
screen.alternate, screen.wrapped = "primary", "primary"
handlers["session.new_window"] = function(args)
  equal(args.session_id, "session:linked")
  equal(args.focus, false)
  check_launch(args, directory)
  fails(function()
    projects.open({}, "/linked/project")
  end, "already opening")
  return { window_id = "window:new", block_ids = { "block:new" } }
end
check_target(open_link("/links/alias", directory), "window:new", "block:new", true)
equal(#queued, queued_before)

sessions = {}
expected_root, expected_directory = os.getenv("HOME"), os.getenv("HOME")
check_target(open_link(expected_root, expected_directory), "window:first", "block:first", true)
equal(sessions[1].label, "main")
sessions = {}
expected_root, expected_directory = "/", directory
check_target(open_link("/", directory), "window:first", "block:first", true)
equal(#queued, queued_before)
os.rename = real_rename
print("Workflow tests passed")
