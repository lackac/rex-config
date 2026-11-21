local root = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/[^/]+$") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local common = require("common")

require("projects").setup()
require("popups").setup()
require("editor").setup()
require("navigation").setup()
require("vendor.rex-hints").setup({ hints = false, jump = false, node = common.tool("node") })
require("vendor.rex-fzf-url").setup({ fzf = common.tool("fzf") })
require("keys").setup()

-- >>> leaf >>>
-- Managed by `leaf rex install`; `leaf rex uninstall` removes it.
-- plugin: 574a512c29e0d37d
dofile("/Users/lackac/.config/rex/plugins/leaf/init.lua").setup({ bin = { "/etc/profiles/per-user/lackac/bin/leaf" } })
-- open: idle classic
-- <<< leaf <<<
