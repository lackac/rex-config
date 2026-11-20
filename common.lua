local M = {}

M.directory = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/") or "."
M.creator = "com.superlogical.terminal"
M.timestamp = os.date("%Y-%m-%d-%H%M%S")

function M.setup() end

local tools
function M.tool(name)
  if name == "rex" and os.getenv("REX_BIN_DIR") then
    return os.getenv("REX_BIN_DIR") .. "/rex"
  end
  if not tools then
    local home = assert(os.getenv("HOME"), "HOME is not set")
    local path = (os.getenv("XDG_DATA_HOME") or home .. "/.local/share") .. "/rex/tools.lua"
    local file = io.open(path, "r")
    if file then
      file:close()
      tools = assert(loadfile(path))()
      assert(type(tools) == "table", "Rex tools.lua must return a table")
    else
      tools = {}
    end
  end
  if tools[name] then
    return tools[name]
  end
  if name == "extrakto" then
    local dir = os.getenv("REX_EXTRAKTO_DIR")
    assert(dir, "Extrakto is not configured; rebuild the Rex tools configuration")
    return dir .. "/extrakto.py"
  end
  local user = os.getenv("USER")
  local dirs = { "/run/current-system/sw/bin", "/opt/homebrew/bin", "/usr/bin", "/bin" }
  if user then
    table.insert(dirs, 1, "/etc/profiles/per-user/" .. user .. "/bin")
  end
  for _, dir in ipairs(dirs) do
    local file = io.open(dir .. "/" .. name, "r")
    if file then
      file:close()
      return dir .. "/" .. name
    end
  end
  return name
end

function M.call(method, args)
  local result, err = rex.call(method, args or {})
  assert(result, err or (method .. " failed"))
  return result
end

function M.app_client(id)
  if not id then
    return nil
  end
  local inspected = M.call("client.inspect", { client_id = id })
  if inspected.client.info and inspected.client.info.kind == "app" then
    return id
  end
end

function M.terminal(origin, method, args)
  return M.call(M.creator .. "." .. method, {
    session_id = origin.session_id,
    block_id = origin.block_id,
    args = args or {},
  })
end

function M.exec(argv, opts)
  local result, err = rex.exec(argv, opts)
  assert(result, err)
  assert(result.ok, result.stderr ~= "" and result.stderr or (argv[1] .. " failed"))
  return result.stdout
end

function M.quote(value)
  assert(type(value) == "string" and not value:find("%z"), "Invalid shell argument")
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.command(argv)
  local quoted = {}
  for i, value in ipairs(argv) do
    quoted[i] = M.quote(value)
  end
  return table.concat(quoted, " ")
end

function M.expand(path)
  assert(type(path) == "string" and path ~= "" and not path:find("[%z\r\n\t]"), "Invalid path")
  if path == "~" then
    return assert(os.getenv("HOME"))
  end
  return (path:gsub("^~/", function()
    return assert(os.getenv("HOME")) .. "/"
  end))
end

function M.canonical(path)
  path = M.expand(path)
  return (
    M.exec({ M.tool("zsh"), "-f", "-c", '[[ -d "$1" ]] && cd -- "$1" && pwd -P', "rex-path", path })
      :gsub("\n$", "")
  )
end

function M.cwd(origin, fallback)
  local process = M.terminal(origin, "process")
  local cwd = process.foreground and process.foreground.cwd or process.child and process.child.cwd
  if cwd then
    return cwd
  end
  local pwd = M.terminal(origin, "pwd").pwd
  if pwd and pwd:match("^file://") then
    pwd = pwd:match("^file://[^/]*(/.*)")
    if pwd then
      pwd = pwd:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
      end)
    end
  end
  if pwd then
    return pwd
  end
  if fallback ~= false then
    return assert(os.getenv("HOME"))
  end
end

function M.origin(ctx)
  assert(ctx.session_id, "This workflow needs a session")
  local view = M.call("session.view", { session_id = ctx.session_id })
  for _, window in ipairs(view.windows or {}) do
    local block_id = ctx.block_id
      or (window.window_id == view.active_window_id and window.focused_block_id)
    for _, layer in ipairs(window.layers or {}) do
      for _, block in ipairs(layer.blocks or {}) do
        if block.block_id == block_id then
          assert(block.creator_name == M.creator, "This workflow needs a terminal")
          local origin = {
            session_id = ctx.session_id,
            window_id = window.window_id,
            block_id = block_id,
            client_id = ctx.client_id,
          }
          origin.cwd = M.cwd(origin)
          return origin, window
        end
      end
    end
  end
  error("The originating terminal is no longer available")
end

function M.layout(cwd, command, keep)
  -- Rex's macOS login(1) launch path ignores command/cwd in preview.21.
  -- Start zsh explicitly so it still reads login/interactive configuration.
  command = command or { M.tool("zsh"), "-il" }
  return rex.layout.block({
    flavor = M.creator .. ".shell",
    options = {
      cwd = cwd,
      command = command,
      shell = "none",
      login = false,
      exit = keep and { on_completion = false } or nil,
    },
  })
end

function M.launch(kind, origin, args)
  local status = M.call("server.status")
  local endpoint = status.listeners and status.listeners[1] and status.listeners[1].endpoint
  assert(endpoint, "Rex did not report its server endpoint")
  local argv = { M.tool("rex"), "--autostart=false", "-S", endpoint }
  local client_id = M.app_client(origin.client_id)
  if client_id then
    argv[#argv + 1] = "-C"
    argv[#argv + 1] = client_id
  end
  argv[#argv + 1] = "do"
  argv[#argv + 1] = "-s"
  argv[#argv + 1] = origin.session_id
  argv[#argv + 1] = "-b"
  argv[#argv + 1] = origin.block_id
  argv[#argv + 1] = M.directory .. "/cli.lua"
  argv[#argv + 1] = "--args"
  argv[#argv + 1] = assert(rex.json.encode({ kind = kind, origin = origin, options = args or {} }))
  local handle, err = rex.exec.start(argv, {
    detach = true,
    env = { REX_CLIENT = client_id or false },
    stdout = false,
    stderr = function(data)
      rex.log("error", "Rex workflow: " .. data)
    end,
  })
  assert(handle, err)
  return { pid = handle.pid }
end

function M.read(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local data = file:read("*a")
  file:close()
  return data
end

function M.write(path, data)
  local file = assert(io.open(path, "wb"))
  assert(file:write(data))
  assert(file:close())
end

-- Each worker owns exactly this directory and its own floating layer. Native
-- close_layer restores the previous focus without selecting a session or tab.
function M.popup(origin, build)
  local root = "/tmp/opencode/rex-workflows"
  M.exec({ "/bin/mkdir", "-p", root })
  local dir = M.exec({ "/usr/bin/mktemp", "-d", root .. "/" .. M.timestamp .. ".XXXXXX" })
    :gsub("\n$", "")
  local layer, files = nil, {}
  local function file(name, data)
    local path = dir .. "/" .. name
    files[#files + 1] = path
    if data ~= nil then
      M.write(path, data)
    end
    return path
  end
  local ok, result = pcall(function()
    M.call("session.attach", { session_id = origin.session_id })
    local command, output = build(file)
    layer = M.call("session.new_layer", {
      session_id = origin.session_id,
      window_id = origin.window_id,
      bounds = { 0.1, 0.1, 0.8, 0.8 },
      focus = true,
      layout = M.layout(origin.cwd, command, true),
    })
    -- Creation claims the pane for this worker at its default 80x24 size.
    -- Let the viewing app claim it and apply its actual terminal dimensions.
    M.call("session.disown_block", {
      session_id = origin.session_id,
      block_ids = layer.block_ids,
    })
    while true do
      local process, err = rex.call(M.creator .. ".process", {
        session_id = origin.session_id,
        block_id = layer.block_ids[1],
        args = {},
      })
      if not process then
        assert(tostring(err):find("not_found"), err or "Cannot inspect floating terminal")
        return nil
      end
      if process.last_exit then
        -- fzf cancellation and failures must never apply a partial output file.
        if process.last_exit.exit_code ~= 0 then
          return nil
        end
        break
      end
      rex.sleep(0.1)
    end
    return output and M.read(output) or nil
  end)
  if layer then
    local closed, err =
      rex.call("session.close_layer", { session_id = origin.session_id, layer_id = layer.layer_id })
    if not closed and err and not tostring(err):find("not_found") then
      rex.log("warn", tostring(err))
    end
  end
  for _, path in ipairs(files) do
    os.remove(path)
  end
  -- rmdir cannot recursively erase files the worker didn't create.
  rex.exec({ "/bin/rmdir", dir })
  assert(ok, result)
  return result
end

function M.fzf(file, candidates, options)
  local input, output = file("candidates", candidates), file("selection")
  local argv = { M.tool("fzf"), "--no-multi", "--layout=reverse", "--border", "--no-ansi" }
  for _, option in ipairs(options or {}) do
    argv[#argv + 1] = option
  end
  local script = M.command(argv) .. " < " .. M.quote(input) .. " > " .. M.quote(output)
  return { M.tool("zsh"), "-f", "-c", script }, output
end

return M
