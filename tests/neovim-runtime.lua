local function test()
  assert(
    (vim.env.REX_SERVER or ""):match("/tmp/opencode/rex%-integration/"),
    "Use a private Rex server: " .. tostring(vim.env.REX_SERVER)
  )
  vim.api.nvim_exec_autocmds("User", { pattern = "DeferredUIEnter" })
  require("smart-splits")
  assert(require("smart-splits.backend").resolve().name == "smart-splits-backend-rex")
  vim.cmd.vsplit()
  vim.cmd("wincmd h")
  local first = vim.api.nvim_get_current_win()
  local move = assert(vim.fn.maparg("<C-Right>", "n", false, true).callback)
  move()
  assert(vim.api.nvim_get_current_win() ~= first, "Ctrl-Right did not navigate inside Neovim")
  move()
  local result = vim
    .system(
      { "rex", "--autostart=false", "session", "inspect", vim.env.REX_SESSION, "--json" },
      { text = true }
    )
    :wait()
  assert(result.code == 0, result.stderr)
  local view = vim.json.decode(result.stdout)
  local neighbor
  for _, block in ipairs(view.windows[1].layers[1].blocks) do
    if block.label == "neighbor" then
      neighbor = block.block_id
    end
  end
  assert(
    neighbor and view.windows[1].focused_block_id == neighbor,
    "Neovim edge did not hand focus to the actual Rex neighbor"
  )
  print("Live Neovim Ctrl-Right: internal split then Rex pane passed")
end

vim.defer_fn(function()
  local ok, err = xpcall(test, debug.traceback)
  if ok then
    vim.cmd("qa!")
  else
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
  end
end, 200)
