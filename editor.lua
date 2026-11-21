local common = require("common")
local M = {}
local label = "Neovim side editor"

local function socket_dir()
  local cache = os.getenv("XDG_CACHE_HOME") or ""
  return (cache:sub(1, 1) == "/" and cache or assert(os.getenv("HOME")) .. "/.cache")
    .. "/rex-editor"
end

local function editor_layout(cwd, script, args, name)
  local command = { common.tool("zsh"), "-lic", script, "rex-editor", unpack(args) }
  local layout = common.layout(cwd, command)
  layout.block.label = name
  return layout
end

local function side_editor(origin)
  local directory = socket_dir()
  common.exec({
    common.tool("zsh"),
    "-fc",
    'umask 077; mkdir -p -- "$1" && [[ -O "$1" && ! -L "$1" ]] && chmod 700 "$1"',
    "rex-editor",
    directory,
  })
  return common.call("session.new_split", {
    session_id = origin.session_id,
    anchor_id = origin.block_id,
    direction = "horizontal",
    side = "before",
    ratio = 0.62,
    focus = true,
    layout = editor_layout(origin.cwd, 'exec nvim --listen "$1/$$.sock"', { directory }, label),
  })
end

local function find_editor(origin, window)
  local found
  for _, layer in ipairs(window.layers or {}) do
    for _, block in ipairs(layer.kind == "tiled" and layer.blocks or {}) do
      if
        block.label == label
        and block.block_id ~= origin.block_id
        and block.creator_name == common.creator
      then
        local process = rex.call(common.creator .. ".process", {
          session_id = origin.session_id,
          block_id = block.block_id,
          args = {},
        })
        local pid = process and process.foreground and process.foreground.pid
        if type(pid) == "number" then
          local socket = socket_dir() .. "/" .. pid .. ".sock"
          local stat = rex.exec({ common.tool("test"), "-S", socket })
          if stat and stat.ok then
            if found then
              return nil -- More than one editor; open a floating pane instead of guessing.
            end
            found = { socket = socket, pane = block.block_id }
          end
        end
      end
    end
  end
  return found
end

local function path(value)
  assert(value:sub(1, 1) == "/" and not value:find("%c"), "Expected an absolute local path")
  return value
end

local function transcript_editor(origin, window, args)
  local file, cwd = path(args.file), path(args.directory)
  local found = find_editor(origin, window)
  if found then
    return found
  end
  local argv = {}
  if args.line then
    argv[1] = ("+call cursor(%d,%d)"):format(args.line, args.column or 1)
  end
  argv[#argv + 1] = "--"
  argv[#argv + 1] = file
  common.call("session.new_layer", {
    session_id = origin.session_id,
    window_id = origin.window_id,
    bounds = { 0.1, 0.1, 0.8, 0.8 },
    focus = true,
    layout = editor_layout(cwd, 'exec nvim "$@"', argv, "Neovim"),
  })
  return { floating = true }
end

function M.setup()
  rex.action({
    name = "split_editor",
    title = "Editor beside pane",
    run = function(ctx)
      return side_editor(common.origin(ctx))
    end,
  })
  rex.action({
    name = "transcript_editor",
    title = "Open transcript file in Neovim",
    args = { directory = "string", file = "string", line = "integer?", column = "integer?" },
    run = function(ctx, args)
      local origin, window = common.origin(ctx)
      return transcript_editor(origin, window, args)
    end,
  })
end

return M
