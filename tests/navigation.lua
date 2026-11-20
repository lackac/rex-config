package.path = "./?.lua;./?/init.lua;" .. package.path

local actions, bindings, queued = {}, {}, {}
local process
local moved = nil
local move_error = nil

rex = {
  action = function(action)
    actions[action.name] = action.run
  end,
  bind = function(key, action, args)
    bindings[key] = { action = action, args = args }
  end,
  block = {
    call = function()
      return process
    end,
  },
  session = {
    focus_direction = function(args)
      moved = args.direction
      return {}, move_error
    end,
  },
  client = {
    queue = function(action, args)
      queued[#queued + 1] = { action = action, args = args }
    end,
  },
}

require("navigation").setup()
local ctx = { block_id = "block:origin" }
for direction, letter in pairs({ left = "h", down = "j", up = "k", right = "l" }) do
  for _, suffix in ipairs({ direction, letter }) do
    local key = "ctrl+" .. suffix
    local binding = assert(bindings[key], "missing binding for " .. key)
    assert(binding.action == "smart_splits_focus")

    queued, moved = {}, nil
    process = { foreground = { name = "zsh", argv0 = "/bin/zsh" } }
    actions[binding.action](ctx, binding.args)
    assert(moved == direction and #queued == 0, key .. " must navigate in Rex")

    moved = nil
    process = { foreground = { name = "editor", argv0 = "/nix/store/neovim/bin/nvim" } }
    actions[binding.action](ctx, binding.args)
    assert(moved == nil and #queued == 1, key .. " must be handed off to Neovim")
    assert(queued[1].action == "pane.send_key" and queued[1].args.key == key)
  end
end

assert(not pcall(actions.smart_splits_focus, ctx, { direction = "left" }))
process = nil
assert(not pcall(actions.smart_splits_focus, ctx, { direction = "left", key = "ctrl+left" }))
assert(not pcall(actions.smart_splits_focus, {}, { direction = "left", key = "ctrl+left" }))

process = { foreground = { name = "zsh" } }
move_error = "session unavailable"
assert(not pcall(actions.smart_splits_focus, ctx, { direction = "left" }))
queued = {}
actions.smart_splits_resize(ctx, { direction = "up" })
assert(queued[1].action == "pane.resize" and queued[1].args.amount == 5)

print("navigation tests passed")
