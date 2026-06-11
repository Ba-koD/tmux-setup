# tmux-setup

Personal tmux setup copied from my server workflow:

- tmux config with mouse support
- default `Ctrl+B` prefix
- zellij-style prefix hint in the status line
- `Ctrl+B ?` key binding popup
- interactive shell session picker on login
- `tx`, `txl`, `txn`, and `codext` helper commands

## Install

```sh
curl -fsSL https://github.com/Ba-koD/tmux-setup/raw/main/install.sh | bash
```

If tmux is already installed and you only want the config:

```sh
curl -fsSL https://github.com/Ba-koD/tmux-setup/raw/main/install.sh | bash -s -- --skip-package-install
```

The installer writes:

```txt
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

## Usage

Open a new interactive shell. The launcher shows existing tmux sessions first.
If `fzf` is installed, it uses an fzf menu. Otherwise, it falls back to a
numbered prompt.

```txt
tmux session> 
[new session]
[native shell]
```

Open the key bindings popup:

```txt
Ctrl+B ?
```

Press `Ctrl+B` once to show the common key hints directly in the status line.
tmux cannot detect a bare `Ctrl` key press by itself, so this is the closest
portable behavior to zellij's key hint mode.

The prefix hint includes common actions such as new window, splits, pane
movement, resize, zoom, window navigation, session/window tree, copy mode,
paste, pane numbers, layout cycling, detach, reload, and the full key popup.

Reload the config from inside tmux:

```txt
Ctrl+B r
```

Helper commands:

```sh
tx        # open the tmux session picker
txl       # list tmux sessions
txn work  # attach to or create a named session
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
