local common = require("common")
local M = {}

function M.setup()
  rex.action({
    name = "popup_lazygit",
    title = "Lazygit",
    run = function(ctx)
      local origin = common.origin(ctx)
      return common.call("session.new_layer", {
        session_id = origin.session_id,
        window_id = origin.window_id,
        bounds = { 0.1, 0.1, 0.8, 0.8 },
        focus = true,
        layout = common.layout(origin.cwd, {
          common.tool("zsh"),
          "-lic",
          'exec "$1"',
          "rex-lazygit",
          common.tool("lazygit"),
        }),
      })
    end,
  })
end

return M
