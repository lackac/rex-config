local root = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/tests/")
package.path = assert(root) .. "/?.lua;" .. package.path
local common = require("common")
local endpoint = common.call("server.status").listeners[1].endpoint
assert(endpoint:match("^unix:///tmp/opencode/rex%-integration/"), "Use a private test server")
local nvim = assert(rex.args.nvim, "Pass the configured Neovim executable as nvim=PATH")
local editor = common.layout(
  "/tmp/opencode",
  { nvim, "--headless", "-c", "luafile " .. root .. "/tests/neovim-runtime.lua" },
  true
)
editor.block.label = "editor"
local neighbor = common.layout("/tmp/opencode", { "/bin/cat" }, true)
neighbor.block.label = "neighbor"
local made = common.call("session.create", {
  label = "Live Neovim navigation test",
  initial_windows = {
    { layout = rex.layout.horizontal(0.6, editor, neighbor) },
  },
})
local id, blocks = made.session_id, made.initial_windows[1].block_ids
local ok, err = pcall(function()
  common.exec({
    common.tool("rex"),
    "--autostart=false",
    "-S",
    endpoint,
    "wait",
    "-s",
    id,
    blocks[1],
    "--for",
    "15s",
  })
  common.call("session.attach", { session_id = id })
  local view = common.call("session.view", { session_id = id })
  assert(
    view.windows[1].focused_block_id == blocks[2],
    "Focus did not cross from Neovim to the actual Rex neighbor"
  )
  common.exec({
    common.tool("rex"),
    "--autostart=false",
    "-S",
    endpoint,
    "do",
    "-s",
    id,
    "-b",
    blocks[2],
    "smart_splits_focus",
    "direction=left",
    "key=ctrl+left",
  })
  view = common.call("session.view", { session_id = id })
  assert(view.windows[1].focused_block_id == blocks[1], "Ordinary Rex pane did not navigate back")
  print(
    "Live smart-splits: Neovim internal movement, handoff to Rex, and generic movement back passed"
  )
end)
common.call("session.attach", { session_id = id })
common.call("session.destroy", { session_id = id })
assert(ok, err)
