# Rex configuration

Lua configuration for a Rex daily-driver trial on lithium. Ghostty and tmux
remain available as a fallback.

## Installation

The checkout lives at `~/Code/lackac/rex-config`. Home Manager in `nix-config`
links `~/.config/rex` to it and writes absolute dependency paths to
`~/.local/share/rex/tools.lua`. The normally installed Rex app owns its server
and updates; Nix supplies the standalone CLI, terminfo, and SSH guard.

Keep the app and its bundled server on Rex's update schedule, independently of
Nix rebuilds. Do not replace the app-owned server with a Nix-pinned version to
work around missing APIs.

The shell and Neovim integration requires Nix activation:

```sh
sudo darwin-rebuild switch --flake "$HOME/Code/lackac/nix-config#lithium" \
  --no-write-lock-file
```

This command is documented, not run automatically. Reload Hammerspoon after
activation to apply its terminal preference changes.

The key-driven project picker selects sessions in the app without a detached
CLI. CLI-driven app selection and tests may still need **Remote Control** in
Rex's **Settings → Rex Server**. Nothing here changes permissions or exposes the
server on the network.

Check edits before reloading:

```sh
rex config check
rex config reload
rex keymap --json
```

The Nix shell integration prioritizes the app's matching `REX_BIN_DIR` and
prevents automatic tmux attachment inside Rex. Outside Rex, its shell function
ignores the shell-specific `XDG_RUNTIME_DIR` so the CLI finds the app's normal
macOS socket. Use `-S` to choose another server explicitly.

## Keys

`Prefix` means **Ctrl+A**, then the next key. **Cmd+K** keeps Rex's native
session picker. Native Cmd-based Rex shortcuts remain available.

| Key | Action |
| --- | --- |
| Ctrl+arrows or Ctrl+H/J/K/L | Smart navigation between Rex panes and Neovim splits |
| Prefix Ctrl+A | Send Ctrl+A to the terminal |
| Prefix `;` or `k` | Project picker |
| Prefix Ctrl+E | Toggle recent session |
| Prefix Ctrl+S | Toggle recent tab within the session |
| Prefix `1`–`9` | Select tab by number |
| Prefix `n` / `p` | Next / previous tab |
| Prefix `c` / `,` | Rex's native New Tab / Rename Tab |
| Prefix `'` | Rex's native Go to Anything picker |
| Prefix `f` / `l` | Rex's native floating pane / floating lazygit |
| Prefix `v` / `g` | Neovim / lazygit in a left split |
| Prefix `m` | Browse manual page names and sections with fzf in a focused right-side 50/50 split |
| Prefix `\|` / `-` | Split right / below |
| Prefix arrows | Focus pane |
| Prefix Shift+H/J/K/L | Resize pane |
| Prefix `r`, then Shift+H/J/K/L | Repeated resizing; Enter or Escape exits |
| Prefix `z` / `x` | Zoom / close pane |
| Prefix Shift+X | Confirm closing the entire session |
| Prefix `[` | Native vi-style copy mode |
| Prefix Ctrl+C / Ctrl+V | Copy current selection / paste clipboard |
| Prefix Tab | Show hints over the focused pane's live screen |
| Prefix `u` | Find web URLs in the focused pane's scrollback with fzf |
| Cmd+F5 | Reload Lua configuration |

Recent-session switching lets Rex choose the destination tab. Prefix `s` is no
longer bound.

Turn off Rex's **Autobalance splits** so the left split opened by Prefix `v` or
`g` takes 62% of the width.

Option+arrows send Alt+B/F; Option+Backspace sends Ctrl+W. The configured
Option-letter editing keys are forwarded as Alt rather than composed symbols.

## Projects and text

The project picker lists live Rex sessions first, followed by zoxide directories.
Type to filter by name or path using Rex's native filter.

A new project session starts with OpenCode and Shell tabs, or only a Shell tab
for the home directory. Reopening a project uses its canonical path and saved
full session ID, so renaming a session or changing a pane's cwd doesn't
duplicate its running work. State lives at `~/.local/state/rex/projects.json`.
Explicit opening is also available:

```sh
rex do project_open path="$HOME/Code/lackac/nix-config"
```

`main` means the home directory. Select it if it appears in the picker, or open
it explicitly with `rex do project_open path="$HOME"`. Opening that path can
reuse an existing home-directory session with another name, such as
`Onboarding`, without renaming it.

Prefix Tab labels paths, URLs, hashes, UUIDs, and IPv4 addresses on the focused
pane's live screen. Type a hint, then press Enter or `c` to copy the match. Hints
do not search scrollback, and a URL wrapped across screen rows may be cut off.

Prefix `u` opens a floating fzf picker for HTTP(S) URLs from the focused pane,
including recent scrollback. It rejoins URLs split by terminal line wrapping.
Enter opens the selection, Ctrl+Y copies it, and Tab marks multiple URLs.

Prefix `o` is no longer bound. See [vendored modules](vendor/README.md) for the
plugin versions and local changes.

## Neovim and Hammerspoon

`nvf-config` installs smart-splits v3 and its Rex and tmux backends. Rex-side
bindings and foreground-Neovim routing live here. `TMUX` takes precedence when
Neovim is deliberately nested inside tmux.

Hammerspoon prefers Rex in terminal cycling and layouts, and recognizes Rex
titles in browser-profile routing. Existing OpenCode session links still open
Ghostty/tmux: their RPC currently requires tmux pane IDs.

## Checks and limits

```sh
luajit tests/navigation.lua
luajit tests/workflows.lua
zsh tests/man-picker.zsh
bash tests/fzf-url.sh
stylua --check .
```

Without a standalone LuaJIT, use `nvim --headless -u NONE -l tests/workflows.lua`
(and the same command for `tests/navigation.lua`).

`tests/runtime.lua` checks project reuse across canonical paths and session
renames, the two-tab layout, pane working directories, and configured tool paths.
Run it only against a private test server, with `XDG_STATE_HOME` under
`/tmp/opencode/rex-integration/`. It runs `cat` in place of project workloads and
closes only its own test sessions.

`tests/neovim-harness.lua nvim=PATH` checks the configured Neovim's real handoff
to a Rex neighbor and generic navigation back. Start the private server with
`REX_SERVER` set to its test socket, just as the Mac app sets it for its server.

`tests/client-regressions.lua` checks visible app selection, numeric tabs,
recent-tab/session toggles, existing and new projects, and `main`. It requires
Hammerspoon IPC for read-only window-title checks, briefly changes the app's
view, and starts a disposable OpenCode session. Pass the app's full client ID
and a session to return to; only sessions created by the check are closed:

```sh
rex -C APP_ID do ./tests/client-regressions.lua \
  client=APP_ID return_session=SESSION_ID
```

Session closing always asks for confirmation: foreground-process information
alone cannot prove that background jobs are safe to terminate. Picker filtering
uses a snapshot; reopen it to refresh. Kill-in-picker is deliberately absent.
Resize amounts are Rex percentages, not tmux cell counts.

In preview.21/22, Rex's macOS `login` launch path ignores a Lua layout's command
and cwd. `common.layout` uses `login = false` and starts zsh explicitly to keep
the requested working directory and login-shell initialization.

Neovim's custom OpenCode pane controls and OpenCode session-link RPC remain
tmux-specific. App relaunch, updater relaunch, server restart, and sleep/wake
persistence still need a hands-on trial with disposable workloads. Restored
layouts do not prove that the original programs survived.
