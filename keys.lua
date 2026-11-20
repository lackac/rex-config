local common = require("common")
local M = {}

local function command_split(origin, argv, side, ratio)
  return common.call("session.new_split", {
    session_id = origin.session_id,
    anchor_id = origin.block_id,
    direction = "horizontal",
    side = side or "before",
    ratio = ratio or 0.62,
    focus = true,
    layout = common.layout(origin.cwd, {
      common.tool("zsh"),
      "-lic",
      'exec "$@"',
      "rex-split",
      unpack(argv),
    }),
  })
end

function M.setup()
  rex.action({
    name = "split_editor",
    title = "Editor beside pane",
    run = function(ctx)
      return command_split(common.origin(ctx), { "nvim" })
    end,
  })
  rex.action({
    name = "split_lazygit",
    title = "Lazygit beside pane",
    run = function(ctx)
      return command_split(common.origin(ctx), { common.tool("lazygit") })
    end,
  })
  rex.action({
    name = "split_man",
    title = "Read manual beside pane",
    run = function(ctx)
      return command_split(common.origin(ctx), {
        common.tool("zsh"),
        "-f",
        common.directory .. "/man-picker.zsh",
        common.tool("fzf"),
      }, "after", 0.5)
    end,
  })

  local bindings = {
    ["ctrl+a"] = { "pane.send_key", { key = "ctrl+a" } },
    [";"] = { "project_picker" },
    k = { "project_picker" },
    ["ctrl+e"] = { "session.recent" },
    ["ctrl+s"] = { "client.tab.recent.in_session" },
    c = { "client.tab.new" },
    [","] = { "client.tab.rename" },
    ["'"] = { "pane.go_to" },
    f = { "pane.new_floating" },
    l = { "popup_lazygit" },
    g = { "split_lazygit" },
    v = { "split_editor" },
    m = { "split_man" },
    ["shift+x"] = { "session_close" },
    ["shift+\\"] = { "pane.split", { direction = "right" } },
    ["-"] = { "pane.split", { direction = "down" } },
    z = { "pane.zoom" },
    x = { "pane.close" },
    ["["] = { "pane.copy_mode.enter" },
    ["ctrl+c"] = { "pane.copy" },
    ["ctrl+v"] = { "pane.paste" },
    tab = { "hints" },
    u = { "fzf_url" },
    n = { "client.tab.next" },
    p = { "client.tab.previous" },
    ["ctrl+alt+h"] = { "client.tab.previous" },
    ["ctrl+alt+l"] = { "client.tab.next" },
    ["ctrl+alt+left"] = { "client.tab.previous" },
    ["ctrl+alt+right"] = { "client.tab.next" },
  }
  for key, binding in pairs(bindings) do
    rex.bind("ctrl+a>" .. key, binding[1], binding[2])
  end
  for index = 1, 9 do
    rex.bind("ctrl+a>" .. index, "client.tab.goto", { index = index })
  end
  for _, direction in ipairs({ "left", "down", "up", "right" }) do
    rex.bind("ctrl+a>" .. direction, "pane.focus", { direction = direction })
  end

  rex.mode("repeat", { exclusive = true })
  rex.bind("ctrl+a>r", "client.mode.enter", { name = "repeat" })
  rex.bind("repeat/enter", "client.mode.exit")
  rex.bind("repeat/esc", "client.mode.exit")
  for key, direction in pairs({
    h = "left",
    j = "down",
    k = "up",
    l = "right",
    [","] = "left",
    ["9"] = "down",
    ["0"] = "up",
    ["."] = "right",
  }) do
    rex.bind("ctrl+a>shift+" .. key, "pane.resize", { direction = direction, amount = 5 })
    rex.bind("repeat/shift+" .. key, "pane.resize", { direction = direction, amount = 5 })
  end

  rex.bind("cmd+f5", "client.config.reload")
  rex.bind("alt+left", "pane.send_key", { key = "alt+b" })
  rex.bind("alt+right", "pane.send_key", { key = "alt+f" })
  rex.bind("alt+backspace", "pane.send_key", { key = "ctrl+w" })
  for _, key in ipairs({ "b", "c", "d", "f", "l", "t", ".", "[", "]" }) do
    rex.bind("alt+" .. key, "pane.send_key", { key = "alt+" .. key })
  end
end

return M
