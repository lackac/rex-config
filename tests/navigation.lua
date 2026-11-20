package.path = "./?.lua;./?/init.lua;" .. package.path

local actions, bindings, queued = {}, {}, {}
local process = { foreground = { name = "zsh", argv0 = "/bin/zsh" } }
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
for _, direction in ipairs({ "left", "down", "up", "right" }) do
  local binding = assert(bindings["ctrl+" .. direction])
  assert(binding.action == "smart_splits_focus")
  assert(binding.args.direction == direction)
  assert(binding.args.key == "ctrl+" .. direction)
end

local ctx = { block_id = "block:origin" }
actions.smart_splits_focus(ctx, bindings["ctrl+left"].args)
assert(moved == "left" and #queued == 0, "ordinary panes must navigate in Rex")

moved = nil
process = { foreground = { name = "editor", argv0 = "/nix/store/neovim/bin/nvim" } }
actions.smart_splits_focus(ctx, bindings["ctrl+right"].args)
assert(moved == nil, "Neovim must receive navigation before Rex handles it")
assert(queued[1].action == "pane.send_key" and queued[1].args.key == "ctrl+right")

assert(not pcall(actions.smart_splits_focus, ctx, { direction = "left" }))
process = nil
assert(not pcall(actions.smart_splits_focus, ctx, { direction = "left", key = "ctrl+left" }))
assert(not pcall(actions.smart_splits_focus, {}, { direction = "left", key = "ctrl+left" }))

process = { foreground = { name = "zsh" } }
move_error = "session unavailable"
assert(not pcall(actions.smart_splits_focus, ctx, { direction = "left" }))
actions.smart_splits_resize(ctx, { direction = "up" })
assert(queued[2].action == "pane.resize" and queued[2].args.amount == 5)

print("navigation tests passed")
