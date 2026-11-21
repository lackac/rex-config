-- Register only the workflow actions, for rex config check without live calls.
local root = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/tests/[^/]+$") or "."
package.path = root .. "/?.lua;" .. package.path
for _, name in ipairs({ "common", "editor", "projects", "popups" }) do
  require(name).setup()
end
