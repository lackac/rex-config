-- Requires Hammerspoon IPC for read-only window-title checks. Restores the app's
-- view and closes only its own sessions, including one disposable OpenCode.
local root = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/tests/")
package.path = assert(root) .. "/?.lua;" .. package.path
local common = require("common")
local client = assert(rex.args.client, "Pass client=APP_ID")
local original = assert(rex.args.return_session, "Pass return_session=ID")
local endpoint = common.call("server.status").listeners[1].endpoint
local base = "/tmp/opencode/rex-integration/client-regressions"
common.exec({ "/bin/mkdir", "-p", base .. "/origin", base .. "/target", base .. "/new-project" })
local made, failures = {}, {}
local function check(name, fn)
  local ok, err = pcall(fn)
  print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or ": " .. tostring(err)))
  if not ok then
    failures[#failures + 1] = name
  end
end
local function create(name)
  local label = "Rex regression " .. name .. " " .. common.timestamp
  local session = common.call("session.create", {
    label = label,
    initial_windows = {
      { window_label = "One", layout = common.layout(base .. "/" .. name, { "/bin/cat" }) },
      { window_label = "Two", layout = common.layout(base .. "/" .. name, { "/bin/cat" }) },
    },
  })
  made[#made + 1] = session.session_id
  common.call("session.attach", { session_id = session.session_id })
  session.label = label
  return session
end
local function view(session)
  return common.call("session.view", { session_id = session.session_id })
end
local function focus(session, index)
  common.call("session.focus_window", {
    session_id = session.session_id,
    window_id = session.initial_windows[index].window_id,
  })
end
local function selected(session, index)
  -- Rex has no selected-session query. Read titles through Hammerspoon without
  -- performing navigation or typing into a terminal to observe the app's view.
  local tab = type(index) == "string" and index or (index == 2 and "Two" or "One")
  local expected = tab .. " - " .. session.label
  for _ = 1, 30 do
    local titles = assert(rex.json.decode(common.exec({
      common.tool("hs"),
      "-c",
      'return hs.json.encode(hs.fnutils.imap(hs.application.find("Rex"):allWindows(), function(w) return w:title() end))',
    })))
    for _, title in ipairs(titles) do
      if
        title == expected
        or (
          index == false
          and (title == session.label or title:sub(-#session.label - 3) == " - " .. session.label)
        )
      then
        return
      end
    end
    rex.sleep(0.05)
  end
  error("App did not display " .. expected)
end
local function cli(...)
  return common.exec({
    common.tool("rex"),
    "--autostart=false",
    "-S",
    endpoint,
    "-C",
    client,
    unpack({ ... }),
  })
end

local ok, err = pcall(function()
  local origin, target = create("origin"), create("target")
  local id = origin.session_id
  local function reset()
    focus(target, 1)
    rex.client.queue("session.select", { session_id = id })
    rex.client.queue("client.tab.goto", { index = 1 })
    selected(origin)
  end

  check("numeric prefix tab bindings", function()
    reset()
    local keymap = assert(rex.json.decode(cli("keymap", "--json")))
    for index = 1, 9 do
      local found
      for _, binding in ipairs(keymap.bindings) do
        if binding.keys[1] == "ctrl+a" and binding.keys[2] == tostring(index) then
          found = binding.action == "client.tab.goto" and binding.args.index == index
        end
      end
      assert(found, "Missing Ctrl+A > " .. index)
      if index <= 2 then
        rex.client.queue("client.tab.goto", { index = index })
        selected(origin, index)
      end
    end
  end)
  check("native session selection baseline", function()
    reset()
    rex.client.queue("session.select", { session_id = target.session_id })
    selected(target)
  end)
  check("project action switches the app", function()
    reset()
    local opened = assert(rex.json.decode(cli("do", "project_open", "path=" .. base .. "/target")))
    assert(opened.session_id == target.session_id, "Existing test project was not reused")
    selected(target)
  end)
  check("both project picker keys bind the named action", function()
    local keymap = assert(rex.json.decode(cli("keymap", "--json")))
    local found = {}
    for _, binding in ipairs(keymap.bindings) do
      if binding.keys[1] == "ctrl+a" and binding.action == "project_picker" then
        found[binding.keys[2]] = true
      end
    end
    assert(found[";"] and found.k, "Missing a project picker binding")
  end)
  check("new project creates two tabs and switches the app", function()
    reset()
    local opened =
      assert(rex.json.decode(cli("do", "project_open", "path=" .. base .. "/new-project")))
    made[#made + 1] = opened.session_id
    local project = view(opened)
    assert(#project.windows == 2, "New project must have OpenCode and Shell tabs")
    assert(project.windows[1].label == "OpenCode" and project.windows[2].label == "Shell")
    selected(project, "OpenCode")
  end)
  check("main selects the home-directory session", function()
    reset()
    local before = {}
    for _, session in ipairs(common.call("session.list").sessions) do
      before[session.session_id] = true
    end
    local opened = assert(rex.json.decode(cli("do", "project_open", "path=" .. os.getenv("HOME"))))
    if not before[opened.session_id] then
      made[#made + 1] = opened.session_id
    end
    local home = view(opened)
    for _, window in ipairs(home.windows) do
      if window.window_id == home.active_window_id then
        selected(home, false)
        return
      end
    end
    error("Home session has no active tab")
  end)
  if rex.args.history == false then
    print("SKIP native recent tab/session toggles (history=false)")
  else
    check("recent tab toggles within a session", function()
      reset()
      rex.client.queue("client.tab.goto", { index = 2 })
      selected(origin, 2)
      common.call("client.perform", {
        client_id = client,
        session_id = id,
        action = "client.tab.recent.in_session",
      })
      selected(origin)
      common.call("client.perform", {
        client_id = client,
        session_id = id,
        action = "client.tab.recent.in_session",
      })
      selected(origin, 2)
    end)
    check("recent session toggles", function()
      reset()
      rex.client.queue("session.select", { session_id = target.session_id })
      selected(target)
      common.call("client.perform", {
        client_id = client,
        session_id = target.session_id,
        action = "session.recent",
      })
      -- Session history chooses the restored tab; tab toggling is checked above.
      selected(origin, false)
      common.call("client.perform", {
        client_id = client,
        session_id = id,
        action = "session.recent",
      })
      selected(target, false)
    end)
  end
end)

-- Remove only registry entries belonging to sessions this check created.
pcall(function()
  local state = (os.getenv("XDG_STATE_HOME") or os.getenv("HOME") .. "/.local/state")
    .. "/rex/projects.json"
  local data = common.read(state)
  if data then
    local entries = assert(rex.json.decode(data))
    for path, id in pairs(entries) do
      for _, owned in ipairs(made) do
        if id == owned then
          entries[path] = nil
        end
      end
    end
    local temporary = common
      .exec({ "/usr/bin/mktemp", state .. "." .. common.timestamp .. ".XXXXXX" })
      :gsub("\n$", "")
    common.write(temporary, assert(rex.json.encode(entries)))
    assert(os.rename(temporary, state))
  end
end)
local restored, restore_err = pcall(rex.client.queue, "session.select", { session_id = original })
for _, id in ipairs(made) do
  common.call("session.attach", { session_id = id })
  common.call("session.destroy", { session_id = id })
end
assert(restored, restore_err)
assert(ok, err)
assert(#failures == 0, table.concat(failures, ", "))
