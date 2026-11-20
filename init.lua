local root = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/[^/]+$") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local common = require("common")

require("projects").setup()
require("popups").setup()
require("sessions").setup()
require("navigation").setup()
require("vendor.rex-hints").setup({ hints = false, jump = false, node = common.tool("node") })
require("vendor.rex-fzf-url").setup({ fzf = common.tool("fzf") })
require("keys").setup()
