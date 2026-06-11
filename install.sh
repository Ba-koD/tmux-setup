#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PROJECT_NAME="tmux-setup"
MARKER_BEGIN="# >>> managed-by:${PROJECT_NAME} >>>"
MARKER_END="# <<< managed-by:${PROJECT_NAME} <<<"
CONFIG_NAME="personal.tmux.conf"

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
  install.sh [--skip-package-install] [--uninstall]

Options:
  --skip-package-install  Do not install tmux automatically when it is missing
  --uninstall             Remove the managed tmux config block and config file
  -h, --help              Show this help

Install:
  curl -fsSL https://raw.githubusercontent.com/Ba-koD/tmux-setup/main/install.sh | bash

After install:
  tmux
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

set-option -g prefix C-b
unbind-key C-a
bind-key C-b send-prefix

set-option -g base-index 1
set-window-option -g pane-base-index 1
set-option -g renumber-windows on

set-option -g mouse on
set-window-option -g mode-keys vi
set-option -g history-limit 100000
set-option -g escape-time 10

set-option -g status-interval 5
set-option -g status-style "bg=colour235,fg=colour250"
set-option -g status-left " #S "
set-option -g status-right " %Y-%m-%d %H:%M "
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

bind-key H resize-pane -L 5
bind-key J resize-pane -D 5
bind-key K resize-pane -U 5
bind-key L resize-pane -R 5
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

main() {
  local skip_package_install=0
  local uninstall=0
  local config_home config_dir managed_conf tmux_conf installed_version supports_popup

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --skip-package-install)
        skip_package_install=1
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
  managed_conf="${config_dir}/${CONFIG_NAME}"
  tmux_conf="${HOME}/.tmux.conf"

  if [[ "$uninstall" -eq 1 ]]; then
    remove_managed_block "$tmux_conf"
    rm -f "$managed_conf"
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
  write_tmux_config "$managed_conf" "$supports_popup"
  write_managed_block "$tmux_conf" "$managed_conf"

  if [[ -n "${TMUX:-}" ]]; then
    tmux source-file "$tmux_conf"
    info "Reloaded active tmux session"
  fi

  info "Installed tmux config: ${managed_conf}"
  info "Prefix key: Ctrl+B"
  info "Key bindings screen: Ctrl+B then ?"
}

main "$@"
