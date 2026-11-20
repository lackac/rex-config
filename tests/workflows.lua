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
equal(#calls, 0)
equal(#commands, 0)

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
local explicit = common.origin({ session_id = origin.session_id, block_id = "block:other" })
equal(explicit.window_id, "window:other")

print("Workflow tests passed")
