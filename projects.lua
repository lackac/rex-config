local common = require("common")
local M = {}
local opening = {}

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
-- Unmanaged sessions are reused only on an exact canonical cwd match.
function M.existing(path, sessions, saved)
  local by_id, managed = {}, {}
  for _, session in ipairs(sessions) do
    by_id[session.session_id] = true
  end
  for _, id in pairs(saved) do
    managed[id] = true
  end
  if saved[path] and by_id[saved[path]] then
    return saved[path]
  end
  for _, session in ipairs(sessions) do
    if not managed[session.session_id] then
      local attached = common.call("session.attach", { session_id = session.session_id })
      for _, window in ipairs(attached.view.windows or {}) do
        for _, layer in ipairs(window.layers or {}) do
          for _, block in ipairs(layer.blocks or {}) do
            if block.creator_name == common.creator then
              local ok, cwd = pcall(
                common.cwd,
                { session_id = session.session_id, block_id = block.block_id },
                false
              )
              if ok and cwd then
                local canonical_ok, canonical = pcall(common.canonical, cwd)
                if canonical_ok and canonical == path then
                  return session.session_id
                end
              end
            end
          end
        end
      end
    end
  end
end

function M.open(ctx, path)
  path = common.canonical(path or assert(os.getenv("HOME")))
  assert(not opening[path], "This project is already opening; try again shortly")
  opening[path] = true
  local ok, result = pcall(function()
    local sessions = common.call("session.list").sessions or {}
    local id = M.existing(path, sessions, registry())
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

function M.candidates()
  local entries, seen = {}, {}
  local saved = registry()
  local paths = {}
  for path, id in pairs(saved) do
    paths[id] = path
  end
  local function add(entry)
    entries[#entries + 1] = entry
    entry.key = tostring(#entries)
  end
  for _, session in ipairs(common.call("session.list").sessions or {}) do
    add({
      source = "sessions",
      label = session.label,
      path = paths[session.session_id] or "",
      session_id = session.session_id,
    })
  end
  local function directory(path, source)
    local ok, canonical = pcall(common.canonical, path)
    if ok and not seen[canonical] then
      seen[canonical] = true
      add({ source = source, label = M.name(canonical), path = canonical })
    end
  end
  directory(assert(os.getenv("HOME")), "configs")
  local home = assert(os.getenv("HOME"))
  local configs = { "nix-config", "nvf-config", "oc-config", "hs-config", "rex-config" }
  for _, name in ipairs(configs) do
    directory(home .. "/Code/lackac/" .. name, "configs")
  end
  local zoxide = rex.exec({ common.tool("zoxide"), "query", "--list" })
  if zoxide and zoxide.ok then
    for path in zoxide.stdout:gmatch("[^\r\n]+") do
      directory(path, "zoxide")
    end
  end
  return entries
end

function M.picker(origin)
  local entries = M.candidates()
  local result = common.popup(origin, function(file)
    local rows, sources = {}, { sessions = {}, configs = {}, zoxide = {} }
    for _, entry in ipairs(entries) do
      local row = table.concat(
        { entry.key, entry.source, display(entry.label), display(entry.path) },
        "\t"
      ) .. "\n"
      rows[#rows + 1] = row
      sources[entry.source][#sources[entry.source] + 1] = row
    end
    local bindings = {}
    sources.all = rows
    for _, pair in ipairs({
      { "ctrl-a", "all" },
      { "ctrl-t", "sessions" },
      { "ctrl-g", "configs" },
      { "ctrl-d", "zoxide" },
    }) do
      local path = file(pair[2], table.concat(sources[pair[2]]))
      bindings[#bindings + 1] = pair[1]
        .. ":reload(cat "
        .. common.quote(path)
        .. ")+change-prompt("
        .. pair[2]
        .. "> )"
    end
    bindings[#bindings + 1] = "ctrl-b:change-nth(2)"
    bindings[#bindings + 1] = "ctrl-p:change-nth(3)"
    return common.fzf(file, table.concat(rows), {
      "--delimiter=\t",
      "--with-nth=2,3,4",
      "--nth=2,3",
      "--prompt=all> ",
      "--header=ctrl-a all / ctrl-t sessions / ctrl-g configs / ctrl-d zoxide | ctrl-b name / ctrl-p path",
      "--bind=" .. table.concat(bindings, ","),
      "--preview=" .. common.command({ common.tool("tree"), "-C", "-L", "2", "--" }) .. " {4}",
    })
  end)
  if not result or result == "" then
    return
  end
  local key = result:match("^(%d+)\t")
  local entry = key and entries[tonumber(key)]
  assert(entry and entry.key == key, "Invalid project selection")
  if entry.session_id then
    common.call("session.attach", { session_id = entry.session_id })
    rex.client.queue("session.select", { session_id = entry.session_id })
    return { session_id = entry.session_id }
  end
  local opened, err = rex.invoke("project_open", { path = entry.path })
  assert(opened, err)
  return opened
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
    run = function(ctx)
      return common.launch("projects", common.origin(ctx))
    end,
  })
end

return M
