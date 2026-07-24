#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bash -n "$ROOT/install.sh"
sh -n "$ROOT/launcher.sh"

if grep -n -e 'fzf' -e 'FZF_' "$ROOT/install.sh" "$ROOT/launcher.sh" "$ROOT/README.md" >/dev/null; then
  fail 'tmux setup must not depend on fzf'
fi

for file in "$ROOT/install.sh" "$ROOT/launcher.sh"; do
  grep -F '_tmux_launcher_keyboard_menu' "$file" >/dev/null || fail "keyboard menu missing from $file"
  grep -F '_tmux_launcher_discard_osc' "$file" >/dev/null || fail "terminal response handling missing from $file"
  grep -F '_tmux_launcher_discard_csi' "$file" >/dev/null || fail "terminal attribute handling missing from $file"
  grep -F 'stty -icanon -echo min 1 time 0' "$file" >/dev/null || fail "raw keyboard input missing from $file"
  grep -F 'dd bs=1 count=1' "$file" >/dev/null || fail "single-key input missing from $file"
done

grep -F 'set-option -g set-clipboard on' "$ROOT/install.sh" >/dev/null || \
  fail 'tmux config must enable terminal clipboard integration'
grep -F 'copy-selection-and-cancel' "$ROOT/install.sh" >/dev/null || \
  fail 'tmux config must copy selections to the system clipboard'
grep -F 'set-option -g default-shell' "$ROOT/install.sh" >/dev/null || \
  fail 'tmux config must launch new panes with the login shell'
grep -F 'resolve_default_shell' "$ROOT/install.sh" >/dev/null || \
  fail 'tmux installer must resolve a usable login shell'
grep -F 'getent passwd' "$ROOT/install.sh" >/dev/null || \
  fail 'tmux installer must prefer the account login shell over the caller shell'

for file in "$ROOT/tmux.conf" "$ROOT/install.sh"; do
  grep -F 'set-option -g escape-time 500' "$file" >/dev/null || \
    fail "tmux must allow terminal query responses to arrive over SSH: $file"
done

grep -F 'git clone https://git.intp.me/rudgh/tmux-setup.git' "$ROOT/README.md" >/dev/null || \
  fail 'README must provide a one-command install from git.intp.me'

printf 'PASS: tmux launcher is fzf-free and keyboard driven\n'
