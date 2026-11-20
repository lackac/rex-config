-- Run from the repository root: luajit tests/workflows.lua
-- Or: nvim --headless -u NONE -l tests/workflows.lua
package.path = "./?.lua;" .. package.path

local actions, calls, commands, queued, json = {}, {}, {}, {}, {}
local handlers = {}
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
      stdout = "/mock/popup\n"
    elseif argv[1] == "/tools/zsh" and argv[3] == "-c" and argv[4]:find("pwd %-P") then
      stdout = argv[6]:gsub("/alias$", "/project") .. "\n"
    elseif argv[1] == "/tools/python3" then
      stdout = "hello\n"
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
  log = function() end,
  sleep = function() end,
  ui = {
    pick = function()
      return nil, "cancelled"
    end,
  },
}

local common = require("common")
require("popups").setup()
equal(#calls, 0)
equal(#commands, 0)
for _, name in ipairs({ "popup_scratch", "popup_lazygit" }) do
  assert(actions[name], "Missing " .. name)
end

common.tool = function(name)
  return "/tools/" .. name
end
equal(common.quote("a'b $(touch nope)"), "'a'\\''b $(touch nope)'")
fails(function()
  common.quote("bad\0argument")
end, "Invalid")
equal(common.canonical("/a directory/alias"), "/a directory/project")
equal(commands[#commands].argv[6], "/a directory/alias")
fails(function()
  common.canonical("/x\ny")
end, "Invalid path")

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
local origin = common.origin({
  session_id = "session:full-origin",
  block_id = "block:origin",
  client_id = "client:origin",
})
equal(origin.window_id, "window:origin")
equal(origin.cwd, "/origin dir")
local exec = rex.exec
handlers["server.status"] = function()
  return { listeners = { { endpoint = "unix:///mock/server.sock" } } }
end
handlers["client.inspect"] = function()
  return { client = { info = { kind = "app" } } }
end
rex.exec = setmetatable({
  start = function(argv, opts)
    equal(argv[1], "/tools/rex")
    equal(argv[2], "--autostart=false")
    equal(argv[3], "-S")
    equal(argv[4], "unix:///mock/server.sock")
    equal(argv[5], "-C")
    equal(argv[6], "client:origin")
    equal(argv[8], "-s")
    equal(argv[9], "session:full-origin")
    equal(argv[10], "-b")
    equal(argv[11], "block:origin")
    equal(argv[12], "./cli.lua")
    local payload = rex.json.decode(argv[14])
    equal(payload.origin.block_id, "block:origin")
    equal(payload.origin.window_id, "window:origin")
    equal(payload.origin.session_id, "session:full-origin")
    equal(opts.detach, true)
    return { pid = 123 }
  end,
}, {
  __call = function(_, ...)
    return exec(...)
  end,
})
equal(common.launch("popup", origin, { popup = "scratch" }).pid, 123)
handlers["client.inspect"] = function()
  return { client = { info = { kind = "cli" } } }
end
equal(common.app_client("client:short-lived-cli"), nil)
handlers["client.inspect"] = function()
  return { client = { info = { kind = "app" } } }
end
local explicit = common.origin({ session_id = origin.session_id, block_id = "block:other" })
equal(explicit.window_id, "window:other")

local memory = {}
local real_rename, real_remove = os.rename, os.remove
os.rename = function(from, to)
  memory[to] = memory[from]
  memory[from] = nil
  return true
end
os.remove = function(path)
  memory[path] = nil
  return true
end
common.read = function(path)
  return memory[path]
end
common.write = function(path, value)
  memory[path] = value
end

local before = #queued

-- Popup cleanup is scoped to its own full IDs; there is no focus/select call.
handlers["session.new_layer"] = function(args)
  equal(args.session_id, origin.session_id)
  equal(args.window_id, origin.window_id)
  equal(args.layout.block.options.cwd, origin.cwd)
  return { layer_id = "layer:owned-popup", block_ids = { "block:owned-popup" } }
end
handlers["session.close_layer"] = function(args)
  equal(args.layer_id, "layer:owned-popup")
  equal(args.session_id, origin.session_id)
  return {}
end
local disowned = false
handlers["session.disown_block"] = function(args)
  equal(args.session_id, origin.session_id)
  equal(#args.block_ids, 1)
  equal(args.block_ids[1], "block:owned-popup")
  disowned = true
  return {}
end
handlers[common.creator .. ".process"] = function(args)
  equal(args.block_id, "block:owned-popup")
  assert(disowned, "The popup worker must release ownership before waiting")
  return { last_exit = { exit_code = 0 } }
end
equal(
  common.popup(origin, function(file)
    local output = file("output", "selected")
    return { "/tools/fzf" }, output
  end),
  "selected"
)
equal(memory["/mock/popup/output"], nil)
handlers[common.creator .. ".process"] = function()
  return { last_exit = { exit_code = 130 } }
end
equal(
  common.popup(origin, function(file)
    return { "/tools/fzf" }, file("output", "partial")
  end),
  nil
)
handlers[common.creator .. ".process"] = function()
  return nil, "not_found: closed"
end
equal(
  common.popup(origin, function(file)
    return { "/tools/fzf" }, file("output", "partial")
  end),
  nil
)
fails(function()
  common.popup(origin, function()
    error("build failed")
  end)
end, "build failed")
equal(commands[#commands].argv[1], "/bin/rmdir")
equal(#queued, before)
os.rename, os.remove = real_rename, real_remove
print("Workflow tests passed")
