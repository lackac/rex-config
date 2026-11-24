# Rex configuration

This Lua configuration for the Rex macOS app adds a project picker, tmux-style
shortcuts, tools for working with terminal text, and Neovim and OpenCode
integrations.

## Quick start

1. Install the Rex macOS app. The app manages its local server and
   updates. Home Manager provides a standalone CLI, terminfo, and an SSH guard;
   it does not manage the macOS app's server.
2. Keep this checkout at `~/Code/lackac/rex-config` for the `nix-config` Home
   Manager module. The module links `~/.config/rex` to the checkout and writes
   absolute tool paths to `${XDG_DATA_HOME:-$HOME/.local/share}/rex/tools.lua`,
   so Rex can find them without the shell's `PATH`. If you manage the setup
   manually, link `~/.config/rex` to the checkout yourself. Use `tools.lua`
   to override paths: return a table mapping tool names to executables.
   For `rex` itself, `REX_BIN_DIR` takes precedence. For tools without an
   entry, the config checks standard Nix, Homebrew, and system locations,
   then uses the bare command name.
3. Open Rex and use **Cmd+K** to choose a session or project. If Rex was
   running when you linked the checkout, run `rex config reload` first.

After editing Lua, run `rex config check ./init.lua` from the checkout, then
reload with **Cmd+F5** in the app or `rex config reload` in a terminal.
Use `rex keymap --json` to inspect the loaded Lua bindings.

The in-app project picker doesn't need **Remote Control**. Enable it in
**Rex → Settings → Rex Server** if you want CLI commands or integrations to
select a session in the app. Home Manager's shell setup prefers the app's
matching CLI when `REX_BIN_DIR` is set and lets `rex` find the app's socket
outside Rex even if the shell sets `XDG_RUNTIME_DIR`. Use `rex -S SERVER` to
target another server explicitly. The managed shell setup skips automatic
tmux attachment inside Rex.

## Open a project

**Cmd+K** lists live Rex sessions first, followed by directories from zoxide,
if available. Type to filter by name or path; reopen the picker to refresh the
list. Choose a session by name to switch to it, or choose a directory to open
a managed project. **Cmd+Shift+K** opens Rex's native session picker instead.

A managed project starts with **OpenCode** and **Shell** tabs. The OpenCode
tab sets `START_OPENCODE=1` for an interactive Zsh. The `nix-config`
OpenCode module uses that flag to start `opencode` after `direnv` loads the
project environment. Press Ctrl+Z to return to the prompt and `fg` to resume.
Without the managed Zsh hook, run `opencode` at the prompt. The config records
the session ID for the directory's canonical path in
`${XDG_STATE_HOME:-$HOME/.local/state}/rex/projects.json`. Opening that
directory again reuses the saved session while it's live, even if you rename
it or change directories in its panes. Sessions you create through Rex's
native commands remain separate, even when they run in the same directory.

To open a directory that isn't in the picker, pass its path explicitly:

```sh
rex do project_open path="$HOME/Code/example-project"
```

Home is also a valid project directory (`path='~'`). This workflow does not
change Rex's native startup behavior.

Home Manager's `terminal-session-name` helper names zoxide entries and new
managed sessions using the same private, untracked rules as tmux:
`${XDG_CONFIG_HOME:-$HOME/.config}/session-name-rules.csv`. If the helper is
unavailable or returns an invalid result, the config uses the directory
basename. It disambiguates new session labels as needed. Changing the rules
does not rename existing sessions.

## Shortcuts

These are the bindings supplied by this config. **Prefix** means press
**Ctrl+A**, release it, then press the next key. Some bindings call native
Rex actions; others run workflows defined here. This guide uses *tab* and
*pane*, which the Rex CLI calls *window* and *block*.

| Direct shortcut | Prefix, then | Action |
| --- | --- | --- |
| Cmd+K | `;` or `k` | Open the configured project picker |
| Cmd+Shift+K | — | Open Rex's native session picker |
| Cmd+E | Ctrl+E | Toggle between recent sessions on the current Rex server |
| — | Ctrl+S | Toggle between the two most recently focused tabs in this session |
| — | `1`–`9` | Select a tab by number |
| — | `n` / `p` | Next / previous tab |
| — | Ctrl+Option+L / Ctrl+Option+H, or Ctrl+Option+Right / Ctrl+Option+Left | Next / previous tab |
| — | `c` / `,` | Rex's native New Tab / Rename Tab |
| — | `'` | Rex's native Go to Anything picker |
| Cmd+Shift+F | `f` | Open a native floating pane |
| Cmd+L | `l` | Open lazygit in a floating pane |
| — | `v` / `g` | Open Neovim / lazygit in a left split |
| — | `m` | Browse manual pages in a right split |
| — | `\|` / `-` | Split right / below |
| Ctrl+arrows or Ctrl+H/J/K/L | — | Move between Rex panes and Neovim splits |
| — | Arrows | Move between Rex panes |
| — | Shift+H/J/K/L | Resize left/down/up/right |
| — | `r`, then resize keys | Resize repeatedly; Enter or Escape exits |
| — | `z` / `x` | Zoom / close pane |
| Ctrl+Cmd+W | Shift+X | Native **File → Close Session** |
| — | `[` | Enter Rex's native vi-style copy mode |
| — | Ctrl+C / Ctrl+V | Copy the current selection / paste from the clipboard |
| — | Tab | Show hints over the focused pane's live screen |
| Cmd+U | `u` | Find web URLs in the focused pane's scrollback |
| — | Ctrl+A | Send Ctrl+A to the terminal |
| Cmd+F5 | — | Reload Lua configuration |

Closing a session can stop every program in it. Do not rely on a server
restart to preserve running processes, even if Rex restores the layout.

## Navigation and text tools

- **Splits:** Use Prefix arrows for native Rex focus or Ctrl+arrows and
  Ctrl+H/J/K/L for smart navigation. Resizing uses five-percentage-point steps,
  not tmux cells. You can also use Shift+`,` / Shift+`9` / Shift+`0` / Shift+`.`
  to resize left/down/up/right, both after Prefix and in repeat mode. Turn
  off Rex's **Autobalance splits** to give the new Neovim or lazygit split
  62% of the width.
- **Manual pages:** Prefix `m` uses fzf to browse page names and sections in
  a focused 50/50 split on the right. Select a match to open its manual page.
- **Hints:** Prefix Tab uses Node to label paths, URLs, hashes, UUIDs, and
  IPv4 addresses on the live screen. Type a hint and press Enter or `c` to
  copy it, or use one of the actions shown for that match. Hints don't search
  scrollback and may cut off a URL that wraps across rows.
- **URL search:** Cmd+U or Prefix `u` opens a floating fzf picker for HTTP(S)
  URLs in the focused pane, including recent scrollback. It rejoins URLs split
  by terminal wrapping. Enter opens the selection, Ctrl+Y copies it, and Tab
  marks multiple URLs.
- **Shell editing:** Option+Left/Right sends Alt+B/F; Option+Backspace sends
  Ctrl+W. Option with `b`, `c`, `d`, `f`, `l`, `t`, `.`, `[`, or `]` sends the
  corresponding Alt key instead of a composed symbol.

## Neovim and OpenCode

`nvf-config` supplies smart-splits v3 and its Rex and tmux backends. Rex moves
focus between ordinary panes and forwards smart navigation keys to foreground
Neovim so it can move within its splits or hand off at the edge. When Neovim
runs inside tmux within Rex, it uses tmux. Its OpenCode V2 pane controls also
prefer tmux when nested:

| In Neovim | Action |
| --- | --- |
| `<leader>as` | Start or focus the OpenCode pane |
| Ctrl+X | Focus the pane and forward OpenCode's native leader key |
| `<leader>aK` | Close the OpenCode pane only if this Neovim instance started it |

With the OpenCode transcript-links plugin, a file link opens in the Neovim
split you started with Prefix `v` in the same Rex tab. If the plugin can't
identify exactly one such split, it opens a floating Neovim pane instead.
The Neovim workflows need `nvim` on the login shell's `PATH`.

This setup's Hammerspoon config prefers Rex for terminal cycling and layouts,
and recognizes Rex window titles when choosing a browser profile. Its
conversation-link helper needs the OpenCode V2 session-link plugin,
**Remote Control** in Rex, and a single local Rex app client.

For an approved `hammerspoon://opencode-session?id=ses_…` link, Rex finds or
creates the managed project. In that project, it reuses a foreground OpenCode
TUI in the conversation's directory or starts one in an OpenCode tab. The
helper asks that exact TUI to open the conversation and waits for confirmation
before it focuses the pane and selects its tab. Hammerspoon then brings Rex
forward.

## Where to make changes

| File | What it controls |
| --- | --- |
| [`init.lua`](init.lua) | Modules Rex loads and options for the vendored text pickers |
| [`keys.lua`](keys.lua) | Cmd and Prefix bindings, resize mode, and lazygit and manual splits |
| [`projects.lua`](projects.lua) | Project picker, naming, saved session reuse, and OpenCode launch targets |
| [`navigation.lua`](navigation.lua) | Smart navigation bindings and Rex-side smart-splits setup |
| [`editor.lua`](editor.lua) | Neovim side splits and transcript file routing |
| [`popups.lua`](popups.lua) | Floating lazygit |
| [`common.lua`](common.lua) | Tool lookup, terminal layouts, and shared path helpers |
| [`man-picker.zsh`](man-picker.zsh) | Manual page catalog and fzf picker |

See [vendored modules](vendor/README.md) for provenance and local changes.

## Checks

Run these from the checkout. The tests use mocks or fixtures, not the
running Rex app.

```sh
luajit tests/navigation.lua
luajit tests/workflows.lua
zsh tests/man-picker.zsh
bash tests/fzf-url.sh
stylua --check .
```

Without standalone LuaJIT, use `nvim --headless -u NONE -l` followed by the
Lua test path.

The [project runtime check](tests/runtime.lua) and
[Neovim navigation harness](tests/neovim-harness.lua) need a private Rex test
server with a socket under `/tmp/opencode/rex-integration/`. For the project
check, isolate `XDG_STATE_HOME` under that directory too. For the Neovim check,
start that server with `REX_SERVER` set to its test socket and pass the configured
Neovim executable as `nvim=PATH`.
