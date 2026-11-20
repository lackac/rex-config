# Vendored modules

`smart-splits-rex.lua` is the unmodified Rex-side module from
[smart-splits-backend-rex](https://github.com/rawnly/smart-splits-backend-rex),
commit `68f54325975ad47b03a968a3f201081bfadc0ff5`, originally at
`rex/lua/smart-splits-rex/init.lua`. Its MIT license is adjacent.

Neovim's matching backend is pinned in `nvf-config`.

[`rex-hints/`](rex-hints/) is from [jmayaalv/rex-hints](https://github.com/jmayaalv/rex-hints),
commit [`9bf180b96f8787c478e8b13f6b65107d92c2ab52`](https://github.com/jmayaalv/rex-hints/commit/9bf180b96f8787c478e8b13f6b65107d92c2ab52)
([MIT](rex-hints/LICENSE)).
The local `init.lua` accepts an absolute Node path and bypasses macOS login
launch. The `hints` executable restores source focus or zoom when it closes
without opening a new pane, and uses the matching Rex CLI from `REX_BIN_DIR`
when available.

[`rex-fzf-url/`](rex-fzf-url/) is from [devert/rex-fzf-url](https://github.com/devert/rex-fzf-url),
commit [`4f47c197ef6aaa63e4a9f5c73aa7a8474604ce0a`](https://github.com/devert/rex-fzf-url/commit/4f47c197ef6aaa63e4a9f5c73aa7a8474604ce0a)
([MIT](rex-fzf-url/LICENSE)).
The local module accepts an explicit fzf executable, uses macOS system paths,
and bypasses macOS login launch. The picker ignores inherited fzf defaults,
limits results to HTTP(S), and preserves balanced URL delimiters.

`keys.lua` owns the shortcuts for both pickers. Rex loads this configuration
without a plugin manager or network access.
