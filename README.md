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

`Prefix` means **Ctrl+A**, then the next key. **Cmd+K** now opens the project
picker. Rex's native session picker moves to **Cmd+Shift+K**.

| Ctrl or Prefix shortcut | Cmd shortcut | Action |
| --- | --- | --- |
| Ctrl+arrows or Ctrl+H/J/K/L | | Smart navigation between Rex panes and Neovim splits |
| Prefix Ctrl+A | | Send Ctrl+A to the terminal |
| Prefix `;` or `k` | Cmd+K | Project picker |
| | Cmd+Shift+K | Rex's native session picker |
| Prefix Ctrl+E | Cmd+E | Toggle recent session |
| Prefix Ctrl+S | | Toggle recent tab within the session |
| Prefix `1`–`9` | | Select tab by number |
| Prefix `n` / `p` | | Next / previous tab |
| Prefix `c` / `,` | | Rex's native New Tab / Rename Tab |
| Prefix `'` | | Rex's native Go to Anything picker |
| Prefix `f` | Cmd+Shift+F | Rex's native floating pane |
| Prefix `l` | Cmd+L | Floating lazygit |
| Prefix `v` / `g` | | Neovim / lazygit in a left split |
| Prefix `m` | | Browse manual page names and sections with fzf in a focused right-side 50/50 split |
| Prefix `\|` / `-` | | Split right / below |
| Prefix arrows | | Focus pane |
| Prefix Shift+H/J/K/L | | Resize pane |
| Prefix `r`, then Shift+H/J/K/L | | Repeated resizing; Enter or Escape exits |
| Prefix `z` / `x` | | Zoom / close pane |
| Prefix Shift+X | Ctrl+Cmd+W | File → Close Session |
| Prefix `[` | | Native vi-style copy mode |
| Prefix Ctrl+C / Ctrl+V | | Copy current selection / paste clipboard |
| Prefix Tab | | Show hints over the focused pane's live screen |
| Prefix `u` | Cmd+U | Find web URLs in the focused pane's scrollback with fzf |
| | Cmd+F5 | Reload Lua configuration |

Recent-session switching lets Rex choose the destination tab. Prefix `s` is no
longer bound.

Turn off Rex's **Autobalance splits** so the left split opened by Prefix `v` or
`g` takes 62% of the width.

Neovim splits opened with Prefix `v` can receive file links from OpenCode.
Without an identifiable editor in the same tab, OpenCode opens the file in a
floating Neovim pane instead.

Option+arrows send Alt+B/F; Option+Backspace sends Ctrl+W. The configured
Option-letter editing keys are forwarded as Alt rather than composed symbols.

## Projects and text

The project picker lists live Rex sessions first, followed by zoxide directories.
Type to filter by name or path using Rex's native filter. Select manual sessions
directly by their label, even when they share a directory with a project.

A new project session starts with OpenCode and Shell tabs, or only a Shell tab
for the home directory. Opening a directory reuses its saved session if it is
still live, even after a rename or a working directory change. Otherwise it
creates a project session, regardless of where manual sessions are running.
Rex stores these associations by canonical path in
`~/.local/state/rex/projects.json`. Explicit opening is also available:

```sh
rex do project_open path="$HOME/Code/example-project"
```

Home Manager installs `terminal-session-name` for picker directories and new
sessions. The helper shares tmux's private, untracked rules at
`${XDG_CONFIG_HOME:-$HOME/.config}/session-name-rules.csv`. If the helper is
unavailable or gives no valid reply, Rex uses the directory basename (`main` for
home). Existing session labels stay as they are. Open home with
`rex do project_open path="$HOME"`.

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

Neovim's OpenCode V2 pane controls work in Rex and tmux. When tmux runs inside
Rex, the controls use tmux. `<leader>as` starts or focuses the OpenCode pane.
Ctrl+X focuses the pane and forwards OpenCode's native leader key.
`<leader>aK` closes the pane only if that Neovim instance started it.

Hammerspoon prefers Rex in terminal cycling and layouts, and recognizes Rex
titles in browser-profile routing. For an approved OpenCode link, the Rex
action `project_open_opencode` takes three required strings: `path` (project
root), `directory` (an existing directory at or below that root), and
`conversation` (the `ses_` ID). For example:

```sh
rex do project_open_opencode path="$project_root" directory="$location" \
  conversation="$session_id" --json
```

The result contains Rex `session_id`, `window_id`, and `block_id` strings and
a `started` boolean. `true` means Rex launched OpenCode in a new tab; `false`
means it found a foreground OpenCode TUI in the matching directory in that
managed project. `started` does not indicate RPC readiness. In either case,
the caller sends the OpenCode session-link RPC to `block_id` and waits for a
matching acknowledgement. Rex does not pass the conversation ID to the
process, select an app session, or focus an existing pane. A link can add a
tab to the home session without changing its shell-only default.

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

`tests/runtime.lua` checks that manual sessions stay separate, projects survive
path aliases and session renames, and tabs, pane directories, and tool paths
are set up correctly.
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

Both session-close shortcuts use Rex's native close logic and can stop all
programs in the session. Picker filtering uses a snapshot; reopen it to refresh.
Kill-in-picker is deliberately absent.
Resize amounts are Rex percentages, not tmux cell counts.

In preview.21/22, Rex's macOS `login` launch path ignores a Lua layout's command
and cwd. `common.layout` uses `login = false` and starts zsh explicitly to keep
the requested working directory and login-shell initialization.

Restarting a private Rex preview.22 server restored the session ID, tab label,
and block ID. The original disposable `sleep` process did not survive; the
restored pane started a fresh zsh shell. The trial did not cover a live server
restart, app relaunch or update, or sleep/wake. Recovery tooling was deliberately
left uninstalled.
