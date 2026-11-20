local common = require("common")
local M = {}

function M.run(origin, kind)
  return common.popup(origin, function()
    local command
    if kind == "lazygit" then
      command = { common.tool("zsh"), "-lic", 'exec "$1"', "rex-lazygit", common.tool("lazygit") }
    else
      command = { common.tool("zsh"), "-il" }
    end
    return command
  end)
end

function M.setup()
  for _, kind in ipairs({ "scratch", "lazygit" }) do
    local popup = kind
    rex.action({
      name = "popup_" .. popup,
      title = popup == "scratch" and "Scratch shell" or "Lazygit",
      run = function(ctx)
        return common.launch("popup", common.origin(ctx), { popup = popup })
      end,
    })
  end
end

return M
