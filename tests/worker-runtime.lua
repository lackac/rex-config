local root = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/tests/")
package.path = assert(root) .. "/?.lua;" .. package.path
local common = require("common")
local status = common.call("server.status")
local endpoint = status.listeners[1].endpoint
assert(endpoint:match("^unix:///tmp/opencode/rex%-integration/"), "Use a private test server")

local made = common.call("session.create", {
  label = "Worker runtime test",
  initial_windows = {
    {
      layout = common.layout("/tmp/opencode", {
        "/bin/sh",
        "-c",
        'printf "%s\\n" "https://example.test/runtime"; exec /bin/cat',
      }, true),
    },
  },
})
local id = made.session_id
local block = made.initial_windows[1].block_ids[1]
local ok, err = pcall(function()
  common.call("session.attach", { session_id = id })
  rex.sleep(0.2)
  local launch_output = common.exec({
    common.tool("rex"),
    "--autostart=false",
    "-S",
    endpoint,
    "do",
    "-s",
    id,
    "-b",
    block,
    "text_picker",
    "mode=urls",
  })
  local ev = rex.wait("block_created", nil, 5)
  assert(ev, "Picker worker did not create its terminal; launch returned " .. launch_output)
  local view = common.call("session.view", { session_id = id })
  local layers = view.windows[1].layers
  assert(#layers == 2, "Expected exactly one floating picker")
  local popup = layers[2].blocks[1].block_id
  for _ = 1, 40 do
    local process = common.terminal({ session_id = id, block_id = popup }, "process")
    if process.foreground and process.foreground.name == "fzf" then
      break
    end
    rex.sleep(0.05)
  end
  local process = common.terminal({ session_id = id, block_id = popup }, "process")
  assert(process.foreground and process.foreground.name == "fzf", "Interactive fzf did not start")
  common.exec({
    common.tool("rex"),
    "--autostart=false",
    "-S",
    endpoint,
    "send-key",
    "-s",
    id,
    "-b",
    popup,
    "ctrl+c",
  })
  local closed = rex.wait("block_closed", { block_id = popup }, 5)
  assert(closed, "Cancelled worker did not clean up its terminal")
  view = common.call("session.view", { session_id = id })
  assert(#view.windows[1].layers == 1)
  assert(view.windows[1].focused_block_id == block)
  common.exec({
    common.tool("rex"),
    "--autostart=false",
    "-S",
    endpoint,
    "do",
    "-s",
    id,
    "-b",
    block,
    "text_picker",
    "mode=urls",
  })
  assert(rex.wait("block_created", nil, 5), "Second text picker did not start")
  view = common.call("session.view", { session_id = id })
  popup = view.windows[1].layers[2].blocks[1].block_id
  for _ = 1, 40 do
    process = common.terminal({ session_id = id, block_id = popup }, "process")
    if process.foreground and process.foreground.name == "fzf" then
      break
    end
    rex.sleep(0.05)
  end
  assert(
    process.foreground and process.foreground.name == "fzf",
    "Second interactive fzf did not start"
  )
  common.exec({
    common.tool("rex"),
    "--autostart=false",
    "-S",
    endpoint,
    "send-key",
    "-s",
    id,
    "-b",
    popup,
    "tab",
  })
  assert(rex.wait("block_closed", { block_id = popup }, 5), "Selected text picker did not close")
  local count = 0
  for _ = 1, 40 do
    local capture = require("text").capture({ session_id = id, block_id = block }, { block })
    local _, matches = capture:gsub("https://example%.test/runtime", "")
    count = matches
    if count >= 2 then
      break
    end
    rex.sleep(0.05)
  end
  assert(count == 2, "Tab did not paste the selected URL into the originating terminal")
  print(
    "Rex worker: server-action launch, explicit endpoint, interactive cancellation, literal insertion and cleanup passed"
  )
end)
common.call("session.attach", { session_id = id })
common.call("session.destroy", { session_id = id })
assert(ok, err)
