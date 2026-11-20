local root = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/[^/]+$") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
