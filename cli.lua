local directory = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/")
if not directory then
  directory = (os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config") .. "/rex"
end
package.path = directory .. "/?.lua;" .. package.path

local args = rex.args or {}
local common = require("common")
local ok, result = pcall(function()
  local origin, options = assert(args.origin, "Missing workflow origin"), args.options or {}
  common.call("session.attach", { session_id = origin.session_id })
  if args.kind == "popup" then
    return require("popups").run(origin, options.popup)
  elseif args.kind == "projects" then
    return require("projects").picker(origin)
  end
  error("Unknown Rex workflow")
end)
if not ok then
  -- Detached workers can outlive the invoking action's stderr callback.
  pcall(function()
    local state = (os.getenv("XDG_STATE_HOME") or os.getenv("HOME") .. "/.local/state") .. "/rex"
    common.exec({ "/bin/mkdir", "-p", state })
    local path = state .. "/workflows.log"
    local log = assert(io.open(path, "ab"))
    common.exec({ "/bin/chmod", "600", path })
    log:write("[" .. common.timestamp .. "] " .. tostring(result) .. "\n")
    log:close()
  end)
  error(result, 0)
end
return result
