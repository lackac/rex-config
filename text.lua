local common = require("common")
local M = {}
local modes =
  { words = "--words", paths = "--paths", urls = "--urls", lines = "--lines", all = "--all" }

function M.capture(origin, blocks)
  local histories = {}
  for _, id in ipairs(blocks) do
    local target = { session_id = origin.session_id, block_id = id }
    local part = common.terminal(
      target,
      "format",
      { format = "text", trim = true, unwrap = true, max_bytes = 960 * 1024 }
    )
    local pieces, offset = { part.content }, #part.content
    while part.id do
      local next_part = common.terminal(
        target,
        "blob_read",
        { id = part.id, offset = offset, max_bytes = 960 * 1024 }
      )
      assert(#next_part.data > 0 or next_part.eof, "Terminal capture made no progress")
      pieces[#pieces + 1] = next_part.data
      offset = offset + #next_part.data
      if next_part.eof then
        break
      end
    end
    histories[#histories + 1] = table.concat(pieces)
  end
  return table.concat(histories, "\n")
end

function M.open_target(value, cwd)
  assert(type(value) == "string" and value ~= "" and not value:find("[%c]"), "Invalid open target")
  local scheme = value:match("^([%a][%w+.-]*):")
  if scheme then
    scheme = scheme:lower()
    assert(
      scheme == "http" or scheme == "https" or scheme == "mailto" or scheme == "file",
      "Refusing unsafe URL scheme"
    )
    if scheme ~= "file" then
      return value
    end
    local host, path = value:match("^[Ff][Ii][Ll][Ee]://([^/]*)(/.*)$")
    assert(host == "" or host == "localhost", "Only local file URLs can be opened")
    value = path:gsub("%%(%x%x)", function(hex)
      return string.char(tonumber(hex, 16))
    end)
    assert(not value:find("[%c]"), "Invalid file URL")
  end
  value = common.expand(value)
  if value:sub(1, 1) ~= "/" then
    value = cwd .. "/" .. value
  end
  local exists = rex.exec({ common.tool("zsh"), "-f", "-c", '[[ -e "$1" ]]', "rex-open", value })
  assert(exists and exists.ok, "Selected path does not exist: " .. value)
  return value
end

function M.apply(origin, key, value)
  assert(
    type(value) == "string" and not value:gsub("\t", ""):find("[%c]"),
    "Selection contains terminal control characters"
  )
  if key == "tab" then
    assert(not value:find("[%c]"), "Cannot insert terminal control characters, including tabs")
    return common.call("block.event", {
      session_id = origin.session_id,
      block_id = origin.block_id,
      event = { type = "paste", payload = { text = value } },
    })
  elseif key == "ctrl-o" then
    return common.exec({ "/usr/bin/open", "--", M.open_target(value, origin.cwd) })
  elseif key == "" or key == "enter" then
    return common.exec({ "/usr/bin/pbcopy" }, { stdin = value })
  end
  error("Unknown text selection action")
end

function M.picker(origin, options)
  assert(modes[options.mode or "all"], "Unknown text mode")
  local history = M.capture(origin, assert(options.blocks, "Missing origin window blocks"))
  local candidates = {}
  for mode, flag in pairs(modes) do
    candidates[mode] = common.exec(
      { common.tool("python3"), common.tool("extrakto"), flag, "--reverse", "--min-length", "1" },
      { stdin = history }
    )
  end
  local result = common.popup(origin, function(file)
    local bindings = {}
    for _, pair in ipairs({
      { "ctrl-a", "all" },
      { "ctrl-w", "words" },
      { "ctrl-p", "paths" },
      { "ctrl-u", "urls" },
      { "ctrl-l", "lines" },
    }) do
      local path = file(pair[2], candidates[pair[2]])
      bindings[#bindings + 1] = pair[1]
        .. ":reload(cat "
        .. common.quote(path)
        .. ")+change-prompt("
        .. pair[2]
        .. "> )"
    end
    return common.fzf(file, candidates[options.mode or "all"], {
      "--expect=tab,ctrl-o",
      "--prompt=" .. (options.mode or "all") .. "> ",
      "--header=Enter copy / Tab insert / ctrl-o open | ctrl-a all / ctrl-w words / ctrl-p paths / ctrl-u URLs / ctrl-l lines",
      "--bind=" .. table.concat(bindings, ","),
    })
  end)
  if not result or result == "" then
    return
  end
  local key, value = result:match("^([^\n]*)\n(.*)\n$")
  assert(key and value and value ~= "", "Invalid text selection")
  local found = false
  for _, list in pairs(candidates) do
    for candidate in list:gmatch("[^\n]+") do
      if candidate == value then
        found = true
        break
      end
    end
  end
  assert(found, "Text selection is not an extracted candidate")
  return M.apply(origin, key, value)
end

function M.setup()
  rex.action({
    name = "text_picker",
    title = "Extract text…",
    args = { mode = "string?" },
    run = function(ctx, args)
      assert(modes[args.mode or "all"], "Unknown text mode")
      local origin, window = common.origin(ctx)
      local blocks = {}
      for _, layer in ipairs(window.layers or {}) do
        for _, block in ipairs(layer.blocks or {}) do
          if block.creator_name == common.creator then
            blocks[#blocks + 1] = block.block_id
          end
        end
      end
      return common.launch("text", origin, { mode = args.mode or "all", blocks = blocks })
    end,
  })
end

return M
