#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PROJECT_NAME="tmux-setup"
MARKER_BEGIN="# >>> managed-by:${PROJECT_NAME} >>>"
MARKER_END="# <<< managed-by:${PROJECT_NAME} <<<"
LAUNCHER_MARKER_BEGIN="# >>> tmux session launcher >>>"
LAUNCHER_MARKER_END="# <<< tmux session launcher <<<"
CONFIG_NAME="personal.tmux.conf"
LAUNCHER_NAME="launcher.sh"

die() {
  printf 'tmux-setup: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

usage() {
  cat <<EOF
Usage:
  install.sh [--skip-package-install] [--no-shell-launcher] [--uninstall]

Options:
  --skip-package-install  Do not install tmux automatically when it is missing
  --no-shell-launcher     Do not add the interactive shell session launcher
  --uninstall             Remove the managed tmux config block and config file
  -h, --help              Show this help

Install:
  curl -fsSL https://raw.githubusercontent.com/Ba-koD/tmux-setup/refs/heads/main/install.sh | bash

After install:
  Open a new interactive shell
  Ctrl+B ?
EOF
}

tmux_quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

version_at_least() {
  local current="$1"
  local minimum="$2"
  local current_major current_minor minimum_major minimum_minor

  current="${current%%[!0-9.]*}"
  current_major="${current%%.*}"
  current_minor="${current#*.}"
  current_minor="${current_minor%%.*}"
  minimum_major="${minimum%%.*}"
  minimum_minor="${minimum#*.}"
  minimum_minor="${minimum_minor%%.*}"

  [[ "$current_major" =~ ^[0-9]+$ ]] || return 1
  [[ "$current_minor" =~ ^[0-9]+$ ]] || current_minor=0

  (( current_major > minimum_major )) && return 0
  (( current_major < minimum_major )) && return 1
  (( current_minor >= minimum_minor ))
}

tmux_version() {
  tmux -V 2>/dev/null | awk '{print $2}'
}

install_tmux_package() {
  local skip_package_install="$1"
  local installed_version

  if command -v tmux >/dev/null 2>&1; then
    installed_version="$(tmux_version)" || die "tmux command exists but cannot run; fix PATH or reinstall tmux"
    [[ -n "$installed_version" ]] || die "tmux command exists but did not print a version"
    info "tmux already installed: tmux ${installed_version}"
    return
  fi

  [[ "$skip_package_install" -eq 0 ]] || die "tmux is not installed; install it manually and rerun this script"

  if command -v brew >/dev/null 2>&1; then
    brew install tmux
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y tmux
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y tmux
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y tmux
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --needed tmux
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y tmux
  else
    die "tmux is not installed and no supported package manager was found"
  fi

  command -v tmux >/dev/null 2>&1 || die "tmux install finished but tmux is still not in PATH"
}

write_tmux_config() {
  local managed_conf="$1"
  local supports_popup="$2"

  cat >"$managed_conf" <<'TMUX_CONF'
# Personal tmux defaults.

set-option -g default-terminal "tmux-256color"
set-option -ga terminal-overrides ",xterm-256color:RGB"
set-option -g mouse on
set-option -g history-limit 50000
set-option -g prefix C-b
unbind-key C-a
bind-key C-b send-prefix

set-option -g base-index 1
set-window-option -g pane-base-index 1
set-option -g renumber-windows on
set-window-option -g mode-keys vi
set-option -g escape-time 10
set-option -g detach-on-destroy off

set-option -g status-interval 1
set-option -g status-style "bg=colour235,fg=colour250"
set-option -g status-left-length 180
set-option -g status-right-length 80
set-option -g status-left "#{?client_prefix,#[reverse] Ctrl+B #[noreverse] c:new  |:split  -:split  h/j/k/l:move  H/J/K/L:resize  x:kill  d:detach  r:reload  ?:keys , #S }"
set-option -g status-right "#{?client_prefix,, %Y-%m-%d %H:%M }"
set-window-option -g window-status-current-style "bg=colour37,fg=colour16"
set-option -g pane-border-style "fg=colour238"
set-option -g pane-active-border-style "fg=colour37"

bind-key r source-file ~/.tmux.conf \; display-message "tmux config reloaded"
bind-key c new-window -c "#{pane_current_path}"
bind-key | split-window -h -c "#{pane_current_path}"
bind-key - split-window -v -c "#{pane_current_path}"

bind-key h select-pane -L
bind-key j select-pane -D
bind-key k select-pane -U
bind-key l select-pane -R

bind-key -r H resize-pane -L 5
bind-key -r J resize-pane -D 2
bind-key -r K resize-pane -U 2
bind-key -r L resize-pane -R 5
TMUX_CONF

  if [[ "$supports_popup" -eq 1 ]]; then
    cat >>"$managed_conf" <<'TMUX_CONF'

bind-key ? display-popup -E -w 90% -h 85% 'sh -c "if command -v less >/dev/null 2>&1; then (tmux list-keys -N 2>/dev/null || tmux list-keys) | less -R; else tmux list-keys -N 2>/dev/null || tmux list-keys; printf \"\\nPress Enter to close...\"; read _; fi"'
TMUX_CONF
  else
    cat >>"$managed_conf" <<'TMUX_CONF'

bind-key ? list-keys -N
TMUX_CONF
  fi
}

write_launcher_script() {
  local launcher_file="$1"

  cat >"$launcher_file" <<'LAUNCHER_SH'
# shellcheck shell=sh

_tmux_launcher_bin_dir="${TMUX_LAUNCHER_BIN_DIR:-$HOME/.local/bin}"
if [ -d "$_tmux_launcher_bin_dir" ]; then
  case ":${PATH:-}:" in
    *":$_tmux_launcher_bin_dir:"*) ;;
    *) PATH="$_tmux_launcher_bin_dir:${PATH:-}"; export PATH ;;
  esac
fi

_tmux_launcher_mktemp() {
  mktemp "${TMPDIR:-/tmp}/tmux-launcher.XXXXXX" 2>/dev/null || mktemp -t tmux-launcher 2>/dev/null
}

_tmux_launcher_in_tmux() {
  [ -n "${TMUX:-}" ]
}

_tmux_launcher_interactive_tty() {
  case $- in
    *i*) ;;
    *) return 1 ;;
  esac
  [ -t 0 ] && [ -t 1 ] && [ -z "${CI:-}" ] && [ -z "${SSH_ORIGINAL_COMMAND:-}" ]
}

_tmux_launcher_sessions() {
  command -v tmux >/dev/null 2>&1 || return 0
  tmux list-sessions -F '#S' 2>/dev/null || true
}

_tmux_launcher_prompt_name() {
  printf 'New tmux session name (empty/q to stay in shell): ' >&2
  IFS= read -r _tmx_name || return 1
  _tmx_trimmed=$(printf '%s' "$_tmx_name" | awk '{$1=$1; print}')
  case $_tmx_trimmed in
    ""|q|Q) return 1 ;;
  esac
  printf '%s\n' "$_tmx_name"
}

_tmux_launcher_attach_or_create() {
  _tmx_session=$1
  command -v tmux >/dev/null 2>&1 || return 0
  tmux new-session -A -s "$_tmx_session"
}

_tmux_launcher_new_session() {
  _tmx_session=$(_tmux_launcher_prompt_name) || return 0
  _tmux_launcher_attach_or_create "$_tmx_session"
}

_tmux_launcher_fzf_menu() {
  _tmx_sessions=$1
  _tmx_choice=$(
    {
      [ -n "$_tmx_sessions" ] && printf '%s\n' "$_tmx_sessions"
      printf '%s\n' '[new session]' '[native shell]'
    } | fzf --prompt='tmux session> ' --height=40% --reverse
  ) || return 0

  case $_tmx_choice in
    ""|"[native shell]") return 0 ;;
    "[new session]") _tmux_launcher_new_session ;;
    *) _tmux_launcher_attach_or_create "$_tmx_choice" ;;
  esac
}

_tmux_launcher_number_menu() {
  _tmx_sessions=$1
  _tmx_tmp=$(_tmux_launcher_mktemp) || return 1
  if [ -n "$_tmx_sessions" ]; then
    printf '%s\n' "$_tmx_sessions" >"$_tmx_tmp"
  else
    : >"$_tmx_tmp"
  fi
  _tmx_count=$(awk 'END { print NR + 0 }' "$_tmx_tmp")

  if [ "$_tmx_count" -gt 0 ] 2>/dev/null; then
    awk '{ printf "%d. %s\n", NR, $0 }' "$_tmx_tmp"
  else
    printf 'No tmux sessions.\n'
  fi
  printf 'n. 새 세션 생성\n'
  printf 'q. native shell 유지\n'
  printf 'Select tmux session: '
  IFS= read -r _tmx_choice || {
    rm -f "$_tmx_tmp"
    return 0
  }

  case $_tmx_choice in
    ""|q|Q)
      rm -f "$_tmx_tmp"
      return 0
      ;;
    n|N)
      rm -f "$_tmx_tmp"
      _tmux_launcher_new_session
      return $?
      ;;
    *[!0-9]*)
      rm -f "$_tmx_tmp"
      return 0
      ;;
  esac

  if [ "$_tmx_choice" -ge 1 ] 2>/dev/null && [ "$_tmx_choice" -le "$_tmx_count" ] 2>/dev/null; then
    _tmx_session=$(awk -v n="$_tmx_choice" 'NR == n { print; exit }' "$_tmx_tmp")
    rm -f "$_tmx_tmp"
    [ -n "$_tmx_session" ] && _tmux_launcher_attach_or_create "$_tmx_session"
    return $?
  fi

  rm -f "$_tmx_tmp"
  return 0
}

tmux_launcher() {
  command -v tmux >/dev/null 2>&1 || return 0
  _tmux_launcher_interactive_tty || return 0
  _tmux_launcher_in_tmux && return 0
  case ${TERM:-} in
    ""|dumb) return 0 ;;
  esac

  _tmx_sessions=$(_tmux_launcher_sessions)

  if command -v fzf >/dev/null 2>&1; then
    _tmux_launcher_fzf_menu "$_tmx_sessions"
  else
    _tmux_launcher_number_menu "$_tmx_sessions"
  fi
}

tx() {
  tmux_launcher
}

txl() {
  command -v tmux >/dev/null 2>&1 || return 0
  tmux list-sessions "$@"
}

txn() {
  command -v tmux >/dev/null 2>&1 || return 0
  if [ "$#" -eq 0 ]; then
    _tmx_session=$(_tmux_launcher_prompt_name) || return 0
  else
    _tmx_session=$*
  fi
  _tmux_launcher_attach_or_create "$_tmx_session"
}

codext() {
  if _tmux_launcher_in_tmux; then
    command codex "$@"
    return $?
  fi

  if ! command -v tmux >/dev/null 2>&1; then
    command codex "$@"
    return $?
  fi

  printf 'Choose or create a tmux session, then run codex inside it.\n'
  tmux_launcher
}
LAUNCHER_SH
}

write_managed_block() {
  local tmux_conf="$1"
  local managed_conf="$2"
  local quoted_managed_conf
  local block_file
  local tmp_file

  quoted_managed_conf="$(tmux_quote "$managed_conf")"
  block_file="$(mktemp)"
  tmp_file="$(mktemp)"

  {
    printf '%s\n' "$MARKER_BEGIN"
    printf 'source-file "%s"\n' "$quoted_managed_conf"
    printf '%s\n' "$MARKER_END"
  } >"$block_file"

  if [[ -f "$tmux_conf" ]] && grep -Fq "$MARKER_BEGIN" "$tmux_conf"; then
    awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" -v block_file="$block_file" '
      $0 == begin {
        while ((getline line < block_file) > 0) {
          print line
        }
        close(block_file)
        skip = 1
        next
      }
      $0 == end {
        skip = 0
        next
      }
      skip != 1 {
        print
      }
    ' "$tmux_conf" >"$tmp_file"
    install -m 0644 "$tmp_file" "$tmux_conf"
  elif [[ -f "$tmux_conf" ]]; then
    {
      printf '\n'
      cat "$block_file"
    } >>"$tmux_conf"
  else
    install -m 0644 "$block_file" "$tmux_conf"
  fi

  rm -f "$block_file" "$tmp_file"
}

write_shell_launcher_block() {
  local shell_conf="$1"
  local block_file
  local tmp_file

  block_file="$(mktemp)"
  tmp_file="$(mktemp)"

  cat >"$block_file" <<'SHELL_BLOCK'
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
SHELL_BLOCK

  if [[ -f "$shell_conf" ]] && grep -Fq "$LAUNCHER_MARKER_BEGIN" "$shell_conf"; then
    awk -v begin="$LAUNCHER_MARKER_BEGIN" -v end="$LAUNCHER_MARKER_END" -v block_file="$block_file" '
      $0 == begin {
        while ((getline line < block_file) > 0) {
          print line
        }
        close(block_file)
        skip = 1
        next
      }
      $0 == end {
        skip = 0
        next
      }
      skip != 1 {
        print
      }
    ' "$shell_conf" >"$tmp_file"
    install -m 0644 "$tmp_file" "$shell_conf"
  elif [[ -f "$shell_conf" ]]; then
    {
      printf '\n'
      cat "$block_file"
    } >>"$shell_conf"
  else
    install -m 0644 "$block_file" "$shell_conf"
  fi

  rm -f "$block_file" "$tmp_file"
}

install_shell_launcher_blocks() {
  local shell_conf

  for shell_conf in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
    write_shell_launcher_block "$shell_conf"
  done
}

remove_managed_block() {
  local tmux_conf="$1"
  local tmp_file

  [[ -f "$tmux_conf" ]] || return 0
  grep -Fq "$MARKER_BEGIN" "$tmux_conf" || return 0

  tmp_file="$(mktemp)"
  awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 == begin {
      skip = 1
      next
    }
    $0 == end {
      skip = 0
      next
    }
    skip != 1 {
      print
    }
  ' "$tmux_conf" >"$tmp_file"
  install -m 0644 "$tmp_file" "$tmux_conf"
  rm -f "$tmp_file"
}

remove_shell_launcher_block() {
  local shell_conf="$1"
  local tmp_file

  [[ -f "$shell_conf" ]] || return 0
  grep -Fq "$LAUNCHER_MARKER_BEGIN" "$shell_conf" || return 0

  tmp_file="$(mktemp)"
  awk -v begin="$LAUNCHER_MARKER_BEGIN" -v end="$LAUNCHER_MARKER_END" '
    $0 == begin {
      skip = 1
      next
    }
    $0 == end {
      skip = 0
      next
    }
    skip != 1 {
      print
    }
  ' "$shell_conf" >"$tmp_file"
  install -m 0644 "$tmp_file" "$shell_conf"
  rm -f "$tmp_file"
}

remove_shell_launcher_blocks() {
  remove_shell_launcher_block "${HOME}/.zshrc"
  remove_shell_launcher_block "${HOME}/.bashrc"
}

main() {
  local skip_package_install=0
  local install_shell_launcher=1
  local uninstall=0
  local config_home config_dir launcher_dir managed_conf launcher_file tmux_conf installed_version supports_popup

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --skip-package-install)
        skip_package_install=1
        ;;
      --no-shell-launcher)
        install_shell_launcher=0
        ;;
      --uninstall)
        uninstall=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
    shift
  done

  config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
  config_dir="${config_home}/tmux"
  launcher_dir="${config_home}/tmux-launcher"
  managed_conf="${config_dir}/${CONFIG_NAME}"
  launcher_file="${launcher_dir}/${LAUNCHER_NAME}"
  tmux_conf="${HOME}/.tmux.conf"

  if [[ "$uninstall" -eq 1 ]]; then
    remove_managed_block "$tmux_conf"
    remove_shell_launcher_blocks
    rm -f "$managed_conf"
    rm -f "$launcher_file"
    rmdir "$launcher_dir" 2>/dev/null || true
    info "Removed managed tmux setup"
    return
  fi

  install_tmux_package "$skip_package_install"

  installed_version="$(tmux_version)"
  supports_popup=0
  if version_at_least "$installed_version" "3.2"; then
    supports_popup=1
  else
    info "tmux ${installed_version} does not support display-popup; using built-in list-keys"
  fi

  install -d -m 0755 "$config_dir"
  install -d -m 0755 "$launcher_dir"
  write_tmux_config "$managed_conf" "$supports_popup"
  write_launcher_script "$launcher_file"
  write_managed_block "$tmux_conf" "$managed_conf"
  if [[ "$install_shell_launcher" -eq 1 ]]; then
    install_shell_launcher_blocks
  fi

  if [[ -n "${TMUX:-}" ]]; then
    tmux source-file "$tmux_conf"
    info "Reloaded active tmux session"
  fi

  info "Installed tmux config: ${managed_conf}"
  info "Installed tmux launcher: ${launcher_file}"
  info "Prefix key: Ctrl+B"
  info "Shell session list: open a new interactive shell, or run tx"
  info "Key bindings screen: Ctrl+B then ?"
}

main "$@"
