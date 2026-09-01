# tmux-setup

Personal tmux setup copied from my server workflow:

- tmux config with mouse support
- default `Ctrl+B` prefix
- visible `Ctrl+B` prefix in the normal status line
- zellij-style prefix hint in the status line with width-aware levels
- `Ctrl+B ?` key binding popup
- colored, keyboard-driven session picker on login
- automatic updates from GitHub, with no prompt to answer
- personal overlay files that installs and updates never overwrite
- `tx`, `txl`, `txn`, `txu`, `txv`, and `codext` helper commands

## Install

```sh
git clone https://git.intp.me/rudgh/tmux-setup.git && bash tmux-setup/install.sh
```

The installer prints the local, latest, and bundled versions on every run, then
asks whether to install, update, or reinstall. In non-interactive shells it uses
the default answer and continues.

If tmux is already installed and you only want the config:

```sh
curl -fsSL https://github.com/Ba-koD/tmux-setup/raw/main/install.sh | bash -s -- --skip-package-install
```

Install a specific GitHub tag:

```sh
curl -fsSL https://github.com/Ba-koD/tmux-setup/raw/v0.5.0/install.sh | bash
```

The installer writes:

```txt
${XDG_CONFIG_HOME:-~/.config}/tmux-setup/version
${XDG_CONFIG_HOME:-~/.config}/tmux-setup/managed.sums
${XDG_CONFIG_HOME:-~/.config}/tmux-setup/shell-launcher
${XDG_CONFIG_HOME:-~/.config}/tmux/personal.tmux.conf
${XDG_CONFIG_HOME:-~/.config}/tmux-launcher/launcher.sh
```

It does not replace your `~/.tmux.conf`, `~/.zshrc`, or `~/.bashrc`. Instead,
it adds or updates managed blocks.

In `~/.tmux.conf`:

```tmux
# >>> managed-by:tmux-setup >>>
source-file "~/.config/tmux/personal.tmux.conf"
# <<< managed-by:tmux-setup <<<

# >>> tmux-setup:local >>>
source-file -q "~/.config/tmux/local.tmux.conf"
# <<< tmux-setup:local <<<
```

In `~/.zshrc` and `~/.bashrc`:

```sh
# >>> tmux session launcher >>>
case $- in
  *i*)
    if [ -f "$HOME/.config/tmux-launcher/launcher.sh" ]; then
      . "$HOME/.config/tmux-launcher/launcher.sh"
      if [ -z "${NO_TMUX:-}" ] && [ -z "${TMUX:-}" ]; then
        tmux_launcher
      fi
    fi
    ;;
esac
# <<< tmux session launcher <<<
```

To install only tmux config without shell auto-launch:

```sh
curl -fsSL https://github.com/Ba-koD/tmux-setup/raw/main/install.sh | bash -s -- --no-shell-launcher
```

Useful installer options:

```sh
--version           # print local/latest/bundled versions
--yes               # accept default prompts
--no-update-check   # skip GitHub version check
--uninstall         # remove managed files and shell blocks
```

## Personal settings that survive updates

`personal.tmux.conf` and `launcher.sh` are generated files. Every update
rewrites them, so put your own settings in the two overlay files instead. The
installer creates them once, loads them last, and never touches them again.

```txt
${XDG_CONFIG_HOME:-~/.config}/tmux/local.tmux.conf     # tmux settings
${XDG_CONFIG_HOME:-~/.config}/tmux-launcher/local.sh   # shell functions
```

`local.tmux.conf` is sourced after `personal.tmux.conf`, so it wins:

```tmux
set-option -g prefix C-a
unbind-key C-b
bind-key C-a send-prefix
```

`local.sh` is sourced at the end of `launcher.sh`, so it can redefine any
launcher function:

```sh
txdev() { _tmux_launcher_attach_or_create dev; }
```

If you edit a generated file anyway, the installer notices. It records a
checksum of everything it writes, so on the next update it:

- keeps your `personal.tmux.conf` and writes the new defaults to
  `personal.tmux.conf.new`
- backs up your `launcher.sh` as `launcher.sh.bak.<timestamp>` before replacing it

Installs made before v0.5.0 have no recorded checksum, so the first update
backs up the previous `personal.tmux.conf` as `personal.tmux.conf.bak.<timestamp>`
before writing the new one.

## Updates

Every login shell checks GitHub in the background of the launcher and installs a
newer release by running the published `install.sh`. There is nothing to
confirm, and the check is throttled so it hits the network at most once every
six hours.

```txt
 tmux-setup  v0.4.1 -> v0.5.0
Installing tmux-setup v0.5.0...
tmux-setup v0.5.0 is active
```

Update by hand at any time:

```sh
txu        # check now and install if a newer release exists
txu -f     # reinstall the latest release even when already current
txv        # show versions, auto-update state, and hand-edited files
```

Tune or disable it:

```sh
TMUX_SETUP_AUTO_UPDATE=0        # report a new version but do not install it
TMUX_SETUP_UPDATE_INTERVAL=0    # check on every shell (default 21600 seconds)
TMUX_SETUP_UPDATE_TIMEOUT=10    # GitHub request timeout (default 3 seconds)
NO_TMUX_UPDATE=1                # skip the check entirely for this shell
```

Updates reuse the flags of the original install, so a setup installed with
`--no-shell-launcher` never gains a shell block behind your back.

Versions before v0.4.0 have no update check at all. Run the installer once on
those machines; every later update is automatic.

## Usage

Open a new interactive shell. The launcher shows existing tmux sessions first,
each in its own color, with the window count and whether a client is attached.
Use the up/down arrows or `j`/`k` to move, `g`/`G` to jump to the ends, Enter to
select, and Esc or `q` to stay in the native shell.

```txt
  tmux / session launcher   v0.5.0

   work                                        3 win attached
   dotfiles                                            1 win
 > new session                            create and attach
   native shell                         skip tmux this time

  up/down|j/k move   enter select   q/esc native shell
```

Set `NO_COLOR=1` for a plain monochrome picker.

Open the key bindings popup:

```txt
Ctrl+B ?
```

Press `Ctrl+B` once to show the common key hints directly in the status line.
tmux cannot detect a bare `Ctrl` key press by itself, so this is the closest
portable behavior to zellij's key hint mode.

When the prefix is not active, the normal status line still shows `Ctrl+B` and
`d:detach` so the prefix and detach flow are visible by default.

The prefix hint includes common actions such as new window, splits, pane
movement, resize, zoom, window navigation, session/window tree, copy mode,
paste, pane numbers, layout cycling, detach, reload, and the full key popup.
The hint changes by terminal width: wide terminals show the full list, medium
terminals show the core workflow, and narrow terminals show a compact subset.

Reload the config from inside tmux:

```txt
Ctrl+B r
```

Helper commands:

```sh
tx        # open the tmux session picker
txl       # list tmux sessions
txn work  # attach to or create a named session
txu       # update tmux-setup now
txv       # show version and auto-update state
codext    # choose/create a tmux session, then run codex inside it
```

Skip the automatic launcher for one shell:

```sh
NO_TMUX=1 zsh
NO_TMUX=1 bash
```

## Uninstall

```sh
curl -fsSL https://github.com/Ba-koD/tmux-setup/raw/main/install.sh | bash -s -- --uninstall
```

Your `local.tmux.conf` and `local.sh` overlays are left in place.
