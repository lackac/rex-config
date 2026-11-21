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

function M.read(path)
  local file, err, code = io.open(path, "rb")
  if not file then
    -- Rex preview.22 returns 1 for every I/O error, with the Go PathError text.
    if code == 2 or (code == 1 and err == "open " .. path .. ": no such file or directory") then
      return nil
    end
    error(err or ("Could not open " .. path))
  end
  local data, read_error = file:read("*a")
  local closed, close_error = file:close()
  assert(data, read_error or ("Could not read " .. path))
  assert(closed, close_error or ("Could not close " .. path))
  return data
end

function M.write(path, data)
  local file = assert(io.open(path, "wb"))
  assert(file:write(data))
  assert(file:close())
end

return M
