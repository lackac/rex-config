local M = {}

function M.setup()
  require("vendor.smart-splits-rex").setup({ resize_amount = 5 })
  for key, direction in pairs({ left = "left", down = "down", up = "up", right = "right" }) do
    rex.bind("ctrl+" .. key, "smart_splits_focus", {
      direction = direction,
      key = "ctrl+" .. key,
    })
  end
end

return M
