# tmux-setup

Personal tmux setup with the default `Ctrl+B` prefix and a zellij-style key
binding popup.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Ba-koD/tmux-setup/main/install.sh | bash
```

If tmux is already installed and you only want the config:

```sh
curl -fsSL https://raw.githubusercontent.com/Ba-koD/tmux-setup/main/install.sh | bash -s -- --skip-package-install
```

The installer writes the managed config to:

```txt
${XDG_CONFIG_HOME:-~/.config}/tmux/personal.tmux.conf
```

It does not replace your `~/.tmux.conf`. Instead, it adds or updates this
managed block:

```tmux
# >>> managed-by:tmux-setup >>>
source-file "~/.config/tmux/personal.tmux.conf"
# <<< managed-by:tmux-setup <<<
```

## Usage

Start tmux:

```sh
tmux
```

Open the key bindings popup:

```txt
Ctrl+B ?
```

Reload the config from inside tmux:

```txt
Ctrl+B r
```

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/Ba-koD/tmux-setup/main/install.sh | bash -s -- --uninstall
```
