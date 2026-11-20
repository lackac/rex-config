local common = require("common")
local M = {}

function M.run(origin)
  return common.popup(origin, function()
    return { common.tool("zsh"), "-lic", 'exec "$1"', "rex-lazygit", common.tool("lazygit") }
  end)
end

function M.setup()
  rex.action({
    name = "popup_lazygit",
    title = "Lazygit",
    run = function(ctx)
      return common.launch("popup", common.origin(ctx))
    end,
  })
end

return M
