local M = {}

function M.setup()
  require("vendor.smart-splits-rex").setup({ resize_amount = 5 })
  for direction, letter in pairs({ left = "h", down = "j", up = "k", right = "l" }) do
    for _, suffix in ipairs({ direction, letter }) do
      local key = "ctrl+" .. suffix
      rex.bind(key, "smart_splits_focus", { direction = direction, key = key })
    end
  end
end

return M
