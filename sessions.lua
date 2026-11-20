local common = require("common")
local M = {}

function M.setup()
  rex.action({
    name = "session_close",
    title = "Close session…",
    description = "Confirm before closing every tab, popup, and background process.",
    run = function(ctx)
      assert(ctx.session_id, "No session to close")
      local id = ctx.session_id
      local view = common.call("session.view", { session_id = id })
      -- process reports the foreground chain, not all background jobs. Never
      -- mistake an idle-looking foreground shell for a provably idle session.
      local choice, why = rex.ui.pick({
        title = "Close " .. (view.label or id) .. " and ALL its tabs?",
        items = {
          { id = "cancel", title = "Keep session" },
          {
            id = "close",
            title = "Close entire session",
            subtitle = "Stops every tab, floating terminal, detached block, and background job.",
          },
        },
      })
      if choice ~= "close" then
        if why and why ~= "cancelled" then
          rex.log("warn", "Session not closed: " .. why)
        end
        return
      end
      common.call("session.attach", { session_id = id })
      return common.call("session.destroy", { session_id = id })
    end,
  })
end

return M
