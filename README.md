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

Enable **Remote Control** in Rex's **Settings → Rex Server**. Background picker
workers need it to select a session in the app. Nothing here changes permissions
or exposes the server on the network.

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
| Ctrl+arrows | Smart navigation between Rex panes and Neovim splits |
| Prefix Ctrl+A | Send Ctrl+A to the terminal |
| Prefix `;` or `k` | Project picker |
| Prefix Ctrl+E | Toggle recent session |
| Prefix Ctrl+S | Toggle recent tab within the session |
| Prefix `1`–`9` | Select tab by number |
| Prefix `n` / `p` | Next / previous tab |
| Prefix `c` / `s` | Named tab / SSH tab |
| Prefix `'` | Rex's native Go to Anything picker |
| Prefix `f` / `l` | Floating scratch shell / lazygit |
| Prefix `v` / `g` | Neovim / lazygit in a left split |
| Prefix `m` | Manual page in a split |
| Prefix `\|` / `-` | Split right / below |
| Prefix arrows | Focus pane |
| Prefix Shift+H/J/K/L | Resize pane |
| Prefix `r`, then Shift+H/J/K/L | Repeated resizing; Enter or Escape exits |
| Prefix `z` / `x` | Zoom / close pane |
| Prefix Shift+X | Confirm closing the entire session |
| Prefix `[` | Native vi-style copy mode |
| Prefix Ctrl+C / Ctrl+V | Copy current selection / paste clipboard |
| Prefix Tab | Extract text from this tab's terminal histories |
| Prefix `o` / `u` | Extract paths / URLs |
| Cmd+F5 | Reload Lua configuration |

Option+arrows send Alt+B/F; Option+Backspace sends Ctrl+W. The configured
Option-letter editing keys are forwarded as Alt rather than composed symbols.

## Projects and text

The project picker combines live Rex sessions, configuration repositories, and
zoxide directories. Ctrl+A shows all; Ctrl+T shows sessions; Ctrl+G shows
configured destinations; Ctrl+D shows zoxide. Ctrl+B searches names and Ctrl+P
searches paths. Directory previews use `tree`.

Opening a project creates OpenCode and Shell tabs. Reopening uses its canonical
path and saved full session ID, so renaming a session or changing a pane's cwd
doesn't duplicate its running work. State lives at
`~/.local/state/rex/projects.json`. Explicit opening is also available:

```sh
rex do project_open path="$HOME/Code/lackac/nix-config"
```

`main` means the home directory. It can reuse an existing home-directory session
with another name, such as `Onboarding`; opening it does not rename that session.

The text picker captures terminal histories in the originating tab, including
floating panes. Enter copies; Tab pastes literal text into the original pane,
without Enter; Ctrl+O opens a local path or HTTP(S)/mailto URL. Control characters
are rejected for insertion. Ctrl+A/W/P/U/L selects all/words/paths/URLs/lines.
Extrakto supplies tokenization; none of the selected text is shell-evaluated.

## Neovim and Hammerspoon

`nvf-config` installs smart-splits v3 and its Rex and tmux backends. Rex-side
bindings and foreground-Neovim routing live here. `TMUX` takes precedence when
Neovim is deliberately nested inside tmux.

Hammerspoon prefers Rex in terminal cycling and layouts, and recognizes Rex
titles in browser-profile routing. Existing OpenCode session links still open
Ghostty/tmux: their RPC currently requires tmux pane IDs.

## Checks and limits

Background worker errors are recorded in `~/.local/state/rex/workflows.log`
(mode 0600), so failures remain visible after the launching key action returns.

```sh
luajit tests/navigation.lua
luajit tests/workflows.lua
stylua --check .
```

Without a standalone LuaJIT, use `nvim --headless -u NONE -l tests/workflows.lua`
(and the same command for `tests/navigation.lua`).

`tests/runtime.lua` checks real project identity, command/cwd propagation, popup
selection/cancellation/cleanup/focus, capture, and tool paths. Run it only against
a private test server, with `XDG_STATE_HOME` under `/tmp/opencode/rex-integration/`.
It substitutes harmless `cat` processes for project workloads and closes only
its own test sessions.
`tests/worker-runtime.lua` additionally exercises launching a real background
worker from a server action and cancelling its interactive fzf terminal.
`tests/neovim-harness.lua nvim=PATH` checks the configured Neovim's real handoff
to a Rex neighbor and generic navigation back. Start the private server with
`REX_SERVER` set to its test socket, just as the Mac app sets it for its server.

`tests/client-regressions.lua` verifies visible app selection, numeric tabs,
existing/new projects, `main`, and popup ownership. It requires Hammerspoon IPC
for read-only window-title checks, briefly changes the app's view, and starts a
disposable OpenCode session. Pass the app's full client ID and a session to return
to; only sessions created by the check are closed:

```sh
rex -C APP_ID do ./tests/client-regressions.lua \
  client=APP_ID return_session=SESSION_ID history=false
```

`history=false` explicitly skips the two native recent-history checks. Omit it
when testing a server that supports those actions.

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

### Native history version blocker

The tested app-bundled preview.21 server (API 18) does not implement
`focus_history.reverse`. Rex lists `session.recent` and
`client.tab.recent.in_session`, but refuses to perform them on this server.
The Ctrl+E/Ctrl+S bindings remain in place; they are not functional on API 18.
Preview.22 (API 19) advertises the required method. Keep the native bindings and
wait for Rex's updater to deliver bundled-server support rather than managing a
separate API version through Nix. Until then, use the session picker and
numeric/next/previous tab navigation.
