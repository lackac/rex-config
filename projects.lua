local common = require("common")
local M = {}
local opening = {}
local picker_limit = 2000

local function state_path()
  return (os.getenv("XDG_STATE_HOME") or assert(os.getenv("HOME")) .. "/.local/state")
    .. "/rex/projects.json"
end

local function registry()
  local text = common.read(state_path())
  if not text then
    return {}
  end
  local data, err = rex.json.decode(text)
  assert(type(data) == "table", err or "Invalid Rex project registry")
  return data
end

local function remember(path, id)
  local target = state_path()
  common.exec({ "/bin/mkdir", "-p", target:match("^(.*)/") })
  local temporary = common
    .exec({ "/usr/bin/mktemp", target .. "." .. common.timestamp .. ".XXXXXX" })
    :gsub("\n$", "")
  -- No yielding subprocess between reading the registry and replacing it.
  local data = registry()
  data[path] = id
  common.write(temporary, assert(rex.json.encode(data)))
  assert(os.rename(temporary, target))
end

function M.name(path)
  if path == os.getenv("HOME") then
    return "main"
  end
  return path:match("([^/]+)$") or path
end

-- Durable path -> full session ID survives renames and changing terminal cwds.
local function live_id(id, sessions)
  if not id then
    return
  end
  for _, session in ipairs(sessions) do
    if session.session_id == id then
      return id
    end
  end
end

function M.open(ctx, path)
  path = common.canonical(path or assert(os.getenv("HOME")))
  assert(not opening[path], "This project is already opening; try again shortly")
  opening[path] = true
  local ok, result = pcall(function()
    local sessions = common.call("session.list").sessions or {}
    local id = live_id(registry()[path], sessions)
    if not id then
      local name = M.name(path)
      for _, session in ipairs(sessions) do
        if session.label == name then
          name = name .. " — " .. path
          break
        end
      end
      local shell = { window_label = "Shell", layout = common.layout(path) }
      local windows = { shell }
      if path ~= common.canonical(assert(os.getenv("HOME"))) then
        local command = {
          common.tool("zsh"),
          "-lic",
          'if command -v "$1" >/dev/null 2>&1; then "$1" exec "$PWD" "$2" -lic opencode; else opencode; fi; exec "$2" -il',
          "rex-opencode",
          common.tool("direnv"),
          common.tool("zsh"),
        }
        windows = {
          { window_label = "OpenCode", layout = common.layout(path, command) },
          shell,
        }
      end
      local created = common.call("session.create", { label = name, initial_windows = windows })
      id = created.session_id
      common.call("session.attach", { session_id = id })
      common.call(
        "session.focus_window",
        { session_id = id, window_id = created.initial_windows[1].window_id }
      )
    end
    remember(path, id)
    return { session_id = id, path = path }
  end)
  opening[path] = nil
  assert(ok, result)
  -- Queue outside pcall. A CLI caller forwards this to its selected app;
  -- ctx.client_id identifies that caller, not necessarily the app itself.
  if ctx.client_id then
    rex.client.queue("session.select", { session_id = result.session_id })
  end
  return result
end

local function display(text)
  return (text:gsub("[%c]", " "))
end

-- Compare only obvious spellings here. Resolving symlinks or ".." can wait
-- until a directory is selected and opened.
local function path_key(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part ~= "." then
      parts[#parts + 1] = part
    end
  end
  return "/" .. table.concat(parts, "/")
end

local function picker(ctx)
  local items, targets, live, seen = {}, {}, {}, {}
  local function add(item, target)
    item.id = tostring(#items + 1)
    items[#items + 1] = item
    targets[item.id] = target
    return item
  end
  for _, session in ipairs(common.call("session.list").sessions or {}) do
    if #items == picker_limit then
      break
    end
    local id = session.session_id
    live[id] = add({
      title = display(session.label or id),
      icon = "terminal",
      detail = "Session",
    }, { session_id = id })
  end
  for path, id in pairs(registry()) do
    if live[id] then
      live[id].subtitle = display(path)
      seen[path_key(path)] = true
    end
  end
  local zoxide = #items < picker_limit
    and rex.exec({ common.tool("zoxide"), "query", "--list" }, { timeout = 3 })
  if zoxide and zoxide.ok then
    for path in zoxide.stdout:gmatch("[^\n]+") do
      if #items == picker_limit then
        break
      end
      if path:sub(1, 1) == "/" and not path:find("[%z\r\t]") then
        local key = path_key(path)
        if not seen[key] then
          seen[key] = true
          add({ title = display(M.name(key)), subtitle = display(path), icon = "folder" }, {
            path = path,
          })
        end
      end
    end
  end

  local choice, why, detail = rex.ui.pick({
    title = "Choose project",
    placeholder = "Filter by name or path",
    items = items,
  })
  if choice == nil then
    if why and why ~= "cancelled" then
      rex.log("warn", "Project picker: " .. why .. (detail and ": " .. detail or ""))
    end
    return
  end
  local target = assert(targets[choice], "Invalid project selection")
  if target.session_id then
    rex.client.queue("session.select", { session_id = target.session_id })
    return target
  end
  return M.open(ctx, target.path)
end

function M.setup()
  rex.action({
    name = "project_open",
    title = "Open project",
    args = { path = "string?" },
    run = function(ctx, args)
      return M.open(ctx, args.path)
    end,
  })
  rex.action({
    name = "project_picker",
    title = "Choose project…",
    run = picker,
  })
end

return M
