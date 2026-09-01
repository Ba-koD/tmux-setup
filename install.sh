#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PROJECT_NAME="tmux-setup"
INSTALLER_VERSION="v0.5.0"
GITHUB_OWNER="Ba-koD"
GITHUB_REPO="tmux-setup"
MARKER_BEGIN="# >>> managed-by:${PROJECT_NAME} >>>"
MARKER_END="# <<< managed-by:${PROJECT_NAME} <<<"
LAUNCHER_MARKER_BEGIN="# >>> tmux session launcher >>>"
LAUNCHER_MARKER_END="# <<< tmux session launcher <<<"
LOCAL_MARKER_BEGIN="# >>> ${PROJECT_NAME}:local >>>"
LOCAL_MARKER_END="# <<< ${PROJECT_NAME}:local <<<"
LEGACY_LAUNCHER_MARKERS=(
  "# >>> tmux session launcher (local) >>>|# <<< tmux session launcher (local) <<<"
)
CONFIG_NAME="personal.tmux.conf"
LAUNCHER_NAME="launcher.sh"
LOCAL_CONFIG_NAME="local.tmux.conf"
LOCAL_LAUNCHER_NAME="local.sh"
SUMS_NAME="managed.sums"
SHELL_FLAG_NAME="shell-launcher"
ORIGINAL_ARGS=("$@")

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
  install.sh [--skip-package-install] [--no-shell-launcher] [--no-update-check] [--yes] [--uninstall]

Options:
  --skip-package-install  Do not install tmux automatically when it is missing
  --no-shell-launcher     Do not add the interactive shell session launcher
  --no-update-check       Do not check GitHub release/tag versions
  -y, --yes               Use default yes for install/update prompts
  --version               Show bundled, local, and latest versions
  --uninstall             Remove the managed tmux config block and config file
  -h, --help              Show this help

Install:
  git clone https://git.intp.me/rudgh/tmux-setup.git && bash tmux-setup/install.sh

Personal settings that updates never overwrite:
  ${XDG_CONFIG_HOME:-~/.config}/tmux/local.tmux.conf
  ${XDG_CONFIG_HOME:-~/.config}/tmux-launcher/local.sh

After install:
  Open a new interactive shell
  Ctrl+B ?
EOF
}

github_raw_url() {
  local ref="$1"
  printf 'https://github.com/%s/%s/raw/%s/install.sh\n' "$GITHUB_OWNER" "$GITHUB_REPO" "$ref"
}

tmux_quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

version_number() {
  local value="$1"
  value="${value#v}"
  value="${value%%[-+]*}"
  printf '%s\n' "$value"
}

numeric_part() {
  case "${1:-}" in
    ""|*[!0-9]*) printf '0\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

version_gt() {
  local newer older
  local newer_major newer_minor newer_patch older_major older_minor older_patch

  newer="$(version_number "$1")"
  older="$(version_number "$2")"

  IFS=. read -r newer_major newer_minor newer_patch _ <<<"$newer"
  IFS=. read -r older_major older_minor older_patch _ <<<"$older"

  newer_major="$(numeric_part "$newer_major")"
  newer_minor="$(numeric_part "$newer_minor")"
  newer_patch="$(numeric_part "$newer_patch")"
  older_major="$(numeric_part "$older_major")"
  older_minor="$(numeric_part "$older_minor")"
  older_patch="$(numeric_part "$older_patch")"

  (( 10#$newer_major > 10#$older_major )) && return 0
  (( 10#$newer_major < 10#$older_major )) && return 1
  (( 10#$newer_minor > 10#$older_minor )) && return 0
  (( 10#$newer_minor < 10#$older_minor )) && return 1
  (( 10#$newer_patch > 10#$older_patch ))
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

latest_github_version() {
  local latest=""
  local release_url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest"
  local tags_url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/tags"

  if command -v curl >/dev/null 2>&1; then
    latest="$(
      curl -fsSL -H 'Accept: application/vnd.github+json' "$release_url" 2>/dev/null |
        sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1 ||
        true
    )"
    if [[ -z "$latest" ]]; then
      latest="$(
        curl -fsSL -H 'Accept: application/vnd.github+json' "$tags_url" 2>/dev/null |
          sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
          head -n 1 ||
          true
      )"
    fi
  fi

  if [[ -z "$latest" ]] && command -v git >/dev/null 2>&1; then
    latest="$(
      git ls-remote --tags --refs "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git" 'v*' 2>/dev/null |
        awk -F/ '{ print $NF }' |
        sort -V 2>/dev/null |
        tail -n 1 ||
        true
    )"
  fi

  printf '%s\n' "${latest:-$INSTALLER_VERSION}"
}

installed_version() {
  local version_file="$1"

  if [[ -s "$version_file" ]]; then
    sed -n '1p' "$version_file"
  else
    printf 'not installed\n'
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default_yes="$2"
  local answer
  local suffix

  if [[ "$default_yes" -eq 1 ]]; then
    suffix='[Y/n]'
  else
    suffix='[y/N]'
  fi

  if ! { true </dev/tty >/dev/tty; } 2>/dev/null; then
    [[ "$default_yes" -eq 1 ]]
    return
  fi

  printf '%s %s ' "$prompt" "$suffix" >/dev/tty
  IFS= read -r answer </dev/tty || answer=""

  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    n|N|no|NO) return 1 ;;
    "") [[ "$default_yes" -eq 1 ]] ;;
    *) return 1 ;;
  esac
}

reexec_latest_installer() {
  local latest="$1"
  local url
  local args=()
  local arg

  command -v curl >/dev/null 2>&1 || die "curl is required to update from GitHub tag ${latest}"

  for arg in "${ORIGINAL_ARGS[@]}"; do
    [[ "$arg" == "--no-update-check" ]] && continue
    args+=("$arg")
  done
  args+=("--no-update-check")

  url="$(github_raw_url "$latest")"
  info "Fetching tmux-setup ${latest}: ${url}"
  curl -fsSL "$url" | bash -s -- "${args[@]}"
  exit $?
}

version_prompt() {
  local version_file="$1"
  local assume_yes="$2"
  local current latest

  current="$(installed_version "$version_file")"
  latest="$(latest_github_version)"

  info "tmux-setup local: ${current}"
  info "tmux-setup latest: ${latest}"
  info "tmux-setup bundled: ${INSTALLER_VERSION}"

  if version_gt "$latest" "$INSTALLER_VERSION"; then
    if [[ "$assume_yes" -eq 1 ]] || prompt_yes_no "Update installer to ${latest} now?" 1; then
      reexec_latest_installer "$latest"
    fi
    info "Update skipped"
    exit 0
  fi

  if [[ "$current" == "$INSTALLER_VERSION" ]]; then
    if [[ "$assume_yes" -eq 1 ]] || prompt_yes_no "Already on ${current}. Reinstall config now?" 0; then
      return 0
    fi
    info "No changes applied"
    exit 0
  fi

  if [[ "$assume_yes" -eq 1 ]] || prompt_yes_no "Install/update local config to ${INSTALLER_VERSION} now?" 1; then
    return 0
  fi

  info "No changes applied"
  exit 0
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

file_sum() {
  local path="$1"

  [[ -f "$path" ]] || return 0
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" 2>/dev/null | awk '{ print $1 }'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" 2>/dev/null | awk '{ print $1 }'
  fi
}

recorded_sum() {
  local key="$1"
  local sums_file="$2"

  [[ -f "$sums_file" ]] || return 0
  awk -v k="$key" '$1 == k { print $2; exit }' "$sums_file"
}

record_sums() {
  local sums_file="$1"
  local managed_conf="$2"
  local launcher_file="$3"

  {
    printf 'conf %s\n' "$(file_sum "$managed_conf")"
    printf 'launcher %s\n' "$(file_sum "$launcher_file")"
  } >"$sums_file"
}

# True when the file differs from what this installer last wrote, which means
# the user edited it by hand and we must not silently throw the edit away.
user_edited() {
  local key="$1"
  local path="$2"
  local sums_file="$3"
  local recorded current

  recorded="$(recorded_sum "$key" "$sums_file")"
  [[ -n "$recorded" ]] || return 1
  [[ -f "$path" ]] || return 1
  current="$(file_sum "$path")"
  [[ -n "$current" ]] || return 1
  [[ "$current" != "$recorded" ]]
}

write_local_launcher_stub() {
  local path="$1"

  if [[ -e "$path" ]]; then
    return 0
  fi

  cat >"$path" <<'LOCAL_SH'
# shellcheck shell=sh
#
# Personal shell overrides for tmux-setup.
#
# launcher.sh sources this file last, and no install or update ever
# overwrites it. Redefine launcher functions or add your own here.
#
# Example: skip the update check on this machine only
#   NO_TMUX_UPDATE=1
#
# Example: your own session shortcut
#   txdev() { _tmux_launcher_attach_or_create dev; }
LOCAL_SH
  chmod 0644 "$path"
  info "Created personal shell overlay: ${path}"
}

write_local_tmux_conf_stub() {
  local path="$1"

  if [[ -e "$path" ]]; then
    return 0
  fi

  cat >"$path" <<'LOCAL_TMUX_CONF'
# Personal tmux settings for tmux-setup.
#
# Loaded after personal.tmux.conf, so anything here wins, and no install
# or update ever overwrites this file.
#
# Example: go back to the Ctrl+A prefix
#   set-option -g prefix C-a
#   unbind-key C-b
#   bind-key C-a send-prefix
LOCAL_TMUX_CONF
  chmod 0644 "$path"
  info "Created personal tmux overlay: ${path}"
}

write_tmux_config() {
  local managed_conf="$1"
  local supports_popup="$2"
  local default_shell="$3"
  local quoted_default_shell

  quoted_default_shell="$(tmux_quote "$default_shell")"

  cat >"$managed_conf" <<TMUX_CONF
# Personal tmux defaults.

set-option -g default-shell "$quoted_default_shell"
set-option -g default-terminal "tmux-256color"
set-option -ga terminal-overrides ",xterm-256color:RGB"
set-option -g mouse on
set-option -g set-clipboard on
set-option -g history-limit 50000
set-option -g prefix C-b
unbind-key C-a
bind-key C-b send-prefix

set-option -g base-index 1
set-window-option -g pane-base-index 1
set-option -g renumber-windows on
set-window-option -g mode-keys vi
set-option -g escape-time 500
set-option -g detach-on-destroy off

set-option -g status-interval 1
set-option -g status-style "bg=colour235,fg=colour250"
set-option -g status-left-length 260
set-option -g status-right-length 80
set-option -g status-left "#{?client_prefix,#{?#{>=:#{client_width},180},#[reverse] Ctrl+B #[noreverse] c:new  |/-:split  h/j/k/l:move  H/J/K/L:resize  z:zoom  x:kill  d:detach  n/p:win  0-9:goto  w:tree  s:sessions  [:copy  ]:paste  q:panes  Spc:layout  r:reload  ?:all,#{?#{>=:#{client_width},120},#[reverse] Ctrl+B #[noreverse] c:new  |/-:split  h/j/k/l:move  z:zoom  x:kill  d:detach  n/p:win  w:tree  [:copy  ]:paste  ?:all,#[reverse] C-b #[noreverse] c:new  |/-:split  h/j/k/l  z:zoom  d:detach  ?:all}},#{?#{>=:#{client_width},100},#[bold] Ctrl+B #[nobold] d:detach  ?:keys  #S,#[bold] C-b #[nobold] d:detach  #S}}"
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

bind-key -T copy-mode-vi v send-keys -X begin-selection
bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection-and-cancel
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

resolve_default_shell() {
  local account_name="${USER:-}"
  local shell_path=""
  local shell_name

  if [[ -z "$account_name" ]]; then
    account_name="$(id -un)"
  fi
  if command -v getent >/dev/null 2>&1; then
    shell_path="$(getent passwd "$account_name" 2>/dev/null | awk -F: 'NR == 1 { print $7 }')"
  fi
  if [[ -n "$shell_path" && -x "$shell_path" ]]; then
    printf '%s\n' "$shell_path"
    return 0
  fi

  shell_path="${SHELL:-}"
  if [[ "$shell_path" != /* ]]; then
    shell_path="$(command -v "$shell_path" 2>/dev/null || true)"
  fi
  if [[ -n "$shell_path" && -x "$shell_path" ]]; then
    printf '%s\n' "$shell_path"
    return 0
  fi

  for shell_name in zsh bash sh; do
    shell_path="$(command -v "$shell_name" 2>/dev/null || true)"
    if [[ -n "$shell_path" && -x "$shell_path" ]]; then
      printf '%s\n' "$shell_path"
      return 0
    fi
  done

  die "could not find a usable shell for tmux panes"
}

write_launcher_script() {
  local launcher_file="$1"

  cat >"$launcher_file" <<'LAUNCHER_SH'
# shellcheck shell=sh

_tmux_setup_version="v0.5.0"
_tmux_setup_owner="Ba-koD"
_tmux_setup_repo="tmux-setup"
_tmux_setup_palette="81,114,213,179,141,80,209,156"

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

_tmux_setup_state_dir()    { printf '%s/tmux-setup\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
_tmux_setup_config_dir()   { printf '%s/tmux\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
_tmux_setup_launcher_dir() { printf '%s/tmux-launcher\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }

_tmux_setup_version_file() {
  printf '%s/version\n' "$(_tmux_setup_state_dir)"
}

_tmux_setup_installed_version() {
  _tmx_setup_version_file=$(_tmux_setup_version_file)
  if [ -s "$_tmx_setup_version_file" ]; then
    sed -n '1p' "$_tmx_setup_version_file"
  else
    printf 'not installed\n'
  fi
}

_tmux_setup_version_number() {
  _tmx_setup_value=$1
  _tmx_setup_value=${_tmx_setup_value#v}
  _tmx_setup_value=${_tmx_setup_value%%[-+]*}
  printf '%s\n' "$_tmx_setup_value"
}

_tmux_setup_version_gt() {
  _tmx_setup_newer=$(_tmux_setup_version_number "$1")
  _tmx_setup_older=$(_tmux_setup_version_number "$2")
  awk -v newer="$_tmx_setup_newer" -v older="$_tmx_setup_older" '
    BEGIN {
      split(newer, n, ".")
      split(older, o, ".")
      for (i = 1; i <= 3; i++) {
        n[i] += 0
        o[i] += 0
        if (n[i] > o[i]) exit 0
        if (n[i] < o[i]) exit 1
      }
      exit 1
    }
  '
}

# ---------------------------------------------------------------------------
# colors
# ---------------------------------------------------------------------------

_tmux_setup_use_color() {
  [ -z "${NO_COLOR:-}" ] || return 1
  case ${TERM:-} in
    ""|dumb) return 1 ;;
  esac
  return 0
}

_tmux_setup_say() {
  case $1 in
    ok)   _tmx_setup_hue=114 ;;
    warn) _tmx_setup_hue=179 ;;
    err)  _tmx_setup_hue=203 ;;
    *)    _tmx_setup_hue=81 ;;
  esac
  if _tmux_setup_use_color; then
    printf '\033[38;5;%sm%s\033[0m\n' "$_tmx_setup_hue" "$2"
  else
    printf '%s\n' "$2"
  fi
}

_tmux_launcher_cols() {
  _tmx_size=$(stty size </dev/tty 2>/dev/null) || _tmx_size=""
  _tmx_ncols=$(printf '%s' "$_tmx_size" | awk '{print $2 + 0}')
  case $_tmx_ncols in
    ''|*[!0-9]*) _tmx_ncols=${COLUMNS:-80} ;;
  esac
  case $_tmx_ncols in
    ''|*[!0-9]*) _tmx_ncols=80 ;;
  esac
  [ "$_tmx_ncols" -ge 24 ] 2>/dev/null || _tmx_ncols=80
  printf '%s\n' "$_tmx_ncols"
}

# Background-colored spaces only, so terminal character widths never matter.
_tmux_launcher_rule() {
  awk -v w="$1" -v pal="$_tmux_setup_palette" -v color="$2" '
    BEGIN {
      esc = sprintf("%c", 27)
      if (color != "1") {
        s = ""; for (i = 0; i < w; i++) s = s "-"
        print s
        exit
      }
      n = split(pal, P, ",")
      out = ""
      for (i = 1; i <= n; i++) {
        len = int(w * i / n) - int(w * (i - 1) / n)
        if (len < 0) len = 0
        s = ""; for (j = 0; j < len; j++) s = s " "
        out = out esc "[48;5;" P[i] "m" s
      }
      print out esc "[0m"
    }'
}

# ---------------------------------------------------------------------------
# automatic updates
# ---------------------------------------------------------------------------

_tmux_setup_shell_launcher_wanted() {
  _tmx_setup_flag="$(_tmux_setup_state_dir)/shell-launcher"
  [ -f "$_tmx_setup_flag" ] || return 0
  [ "$(sed -n '1p' "$_tmx_setup_flag" 2>/dev/null)" != "0" ]
}

_tmux_setup_should_check() {
  _tmx_setup_interval=${TMUX_SETUP_UPDATE_INTERVAL:-21600}
  case $_tmx_setup_interval in
    ''|*[!0-9]*) _tmx_setup_interval=21600 ;;
  esac
  [ "$_tmx_setup_interval" -eq 0 ] && return 0
  _tmx_setup_stamp="$(_tmux_setup_state_dir)/last-update-check"
  [ -f "$_tmx_setup_stamp" ] || return 0
  _tmx_setup_then=$(sed -n '1p' "$_tmx_setup_stamp" 2>/dev/null)
  case $_tmx_setup_then in
    ''|*[!0-9]*) return 0 ;;
  esac
  [ $(( $(date +%s) - _tmx_setup_then )) -ge "$_tmx_setup_interval" ]
}

_tmux_setup_touch_check() {
  _tmx_setup_dir=$(_tmux_setup_state_dir)
  mkdir -p "$_tmx_setup_dir" 2>/dev/null || return 0
  date +%s >"$_tmx_setup_dir/last-update-check" 2>/dev/null || :
}

_tmux_setup_latest_version() {
  command -v curl >/dev/null 2>&1 || return 0
  _tmx_setup_timeout=${TMUX_SETUP_UPDATE_TIMEOUT:-3}
  case $_tmx_setup_timeout in
    ''|*[!0-9]*) _tmx_setup_timeout=3 ;;
  esac
  _tmx_setup_release_url="https://api.github.com/repos/${_tmux_setup_owner}/${_tmux_setup_repo}/releases/latest"
  _tmx_setup_tags_url="https://api.github.com/repos/${_tmux_setup_owner}/${_tmux_setup_repo}/tags"

  _tmx_setup_latest=$(
    curl -fsSL --max-time "$_tmx_setup_timeout" -H 'Accept: application/vnd.github+json' \
      "$_tmx_setup_release_url" 2>/dev/null |
      sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
  )
  if [ -z "$_tmx_setup_latest" ]; then
    _tmx_setup_latest=$(
      curl -fsSL --max-time "$_tmx_setup_timeout" -H 'Accept: application/vnd.github+json' \
        "$_tmx_setup_tags_url" 2>/dev/null |
        sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
    )
  fi
  printf '%s\n' "$_tmx_setup_latest"
}

# The installer keeps hand-edited config files; see managed.sums there.
_tmux_setup_run_update() {
  _tmx_setup_target=$1
  _tmx_setup_url="https://github.com/${_tmux_setup_owner}/${_tmux_setup_repo}/raw/${_tmx_setup_target}/install.sh"

  if ! command -v curl >/dev/null 2>&1; then
    _tmux_setup_say err 'tmux-setup update needs curl'
    return 1
  fi

  set -- --skip-package-install --yes --no-update-check
  _tmux_setup_shell_launcher_wanted || set -- "$@" --no-shell-launcher

  _tmux_setup_say info "Installing tmux-setup ${_tmx_setup_target}..."
  if ! curl -fsSL --max-time 60 "$_tmx_setup_url" | bash -s -- "$@"; then
    _tmux_setup_say err 'tmux-setup update failed; keeping the current install'
    return 1
  fi

  _tmux_setup_say ok "tmux-setup ${_tmx_setup_target} is active"

  # Load the freshly written launcher into this shell.
  _tmx_setup_new_launcher="$(_tmux_setup_launcher_dir)/launcher.sh"
  [ -f "$_tmx_setup_new_launcher" ] && . "$_tmx_setup_new_launcher"
  return 0
}

_tmux_setup_check_update() {
  [ -z "${NO_TMUX_UPDATE:-}" ] || return 0
  [ -z "${_TMUX_SETUP_UPDATE_CHECKED:-}" ] || return 0
  _tmux_launcher_interactive_tty || return 0
  _tmux_launcher_in_tmux && return 0

  _TMUX_SETUP_UPDATE_CHECKED=1
  export _TMUX_SETUP_UPDATE_CHECKED

  _tmux_setup_should_check || return 0
  _tmx_setup_latest=$(_tmux_setup_latest_version)
  _tmux_setup_touch_check
  [ -n "$_tmx_setup_latest" ] || return 0

  _tmx_setup_current=$(_tmux_setup_installed_version)
  _tmux_setup_version_gt "$_tmx_setup_latest" "$_tmx_setup_current" || return 0

  if _tmux_setup_use_color; then
    printf '\033[1;38;5;213m tmux-setup \033[0m \033[38;5;245m%s\033[0m \033[38;5;245m->\033[0m \033[1;38;5;114m%s\033[0m\n' \
      "$_tmx_setup_current" "$_tmx_setup_latest"
  else
    printf 'tmux-setup %s -> %s\n' "$_tmx_setup_current" "$_tmx_setup_latest"
  fi

  if [ "${TMUX_SETUP_AUTO_UPDATE:-1}" = "0" ]; then
    _tmux_setup_say warn 'Automatic update is off; run txu to update.'
    return 0
  fi

  _tmux_setup_run_update "$_tmx_setup_latest" || :
}

# ---------------------------------------------------------------------------
# session picker
# ---------------------------------------------------------------------------

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

_tmux_launcher_session_details() {
  command -v tmux >/dev/null 2>&1 || return 0
  _tmx_unit=$(printf '\034')
  tmux list-sessions \
    -F "#{session_name}${_tmx_unit}#{session_windows} win#{?session_attached, attached,}" 2>/dev/null || true
}

_tmux_launcher_prompt_name() {
  if _tmux_setup_use_color; then
    printf '\033[1;38;5;114m+\033[0m \033[1mNew tmux session name\033[0m \033[38;5;245m(empty or q to stay in the shell)\033[0m\n  \033[38;5;114m>\033[0m ' >&2
  else
    printf 'New tmux session name (empty/q to stay in shell): ' >&2
  fi
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

_tmux_launcher_keyboard_select() (
  _tmx_sessions=$1
  _tmx_tmp=$(_tmux_launcher_mktemp) || return 1
  _tmx_info=$(_tmux_launcher_mktemp) || { rm -f "$_tmx_tmp"; return 1; }
  _tmx_unit=$(printf '\034')

  _tmux_launcher_session_details >"$_tmx_info" 2>/dev/null || :

  # kind <TAB> value <TAB> label <TAB> detail
  {
    if [ -n "$_tmx_sessions" ]; then
      printf '%s\n' "$_tmx_sessions" | while IFS= read -r _tmx_row; do
        [ -n "$_tmx_row" ] || continue
        _tmx_detail=$(awk -F"$_tmx_unit" -v n="$_tmx_row" '$1 == n { print $2; exit }' "$_tmx_info")
        printf 's\t%s\t%s\t%s\n' "$_tmx_row" "$_tmx_row" "$_tmx_detail"
      done
    fi
    printf 'n\t[new session]\tnew session\tcreate and attach\n'
    printf 'q\t[native shell]\tnative shell\tskip tmux this time\n'
  } >"$_tmx_tmp"

  _tmx_count=$(awk 'END { print NR + 0 }' "$_tmx_tmp")
  _tmx_selected=1
  _tmx_escape=$(printf '\033')
  if _tmux_setup_use_color; then _tmx_color=1; else _tmx_color=0; fi
  _tmx_version=$(_tmux_setup_installed_version 2>/dev/null || printf '')

  _tmx_tty_state=$(stty -g </dev/tty) || {
    rm -f "$_tmx_tmp" "$_tmx_info"
    return 1
  }
  _tmux_launcher_keyboard_cleanup() {
    stty "$_tmx_tty_state" </dev/tty 2>/dev/null || :
    printf '\033[?25h\033[?1049l' >/dev/tty
    rm -f "$_tmx_tmp" "$_tmx_info"
  }
  _tmux_launcher_discard_osc() {
    while :; do
      _tmx_osc_char=$(dd bs=1 count=1 </dev/tty 2>/dev/null) || return 0
      [ -n "$_tmx_osc_char" ] || return 0
      [ "$_tmx_osc_char" = "$(printf '\a')" ] && return 0
      if [ "$_tmx_osc_char" = "$_tmx_escape" ]; then
        _tmx_osc_end=$(dd bs=1 count=1 </dev/tty 2>/dev/null) || return 0
        [ "$_tmx_osc_end" = '\' ] && return 0
      fi
    done
  }
  _tmux_launcher_discard_csi() {
    while :; do
      _tmx_csi_char=$(dd bs=1 count=1 </dev/tty 2>/dev/null) || return 0
      [ -n "$_tmx_csi_char" ] || return 0
      case $_tmx_csi_char in
        [@-~]) return 0 ;;
      esac
    done
  }
  _tmux_launcher_draw() {
    _tmx_cols=$(_tmux_launcher_cols)
    _tmx_width=$((_tmx_cols - 4))
    [ "$_tmx_width" -gt 62 ] && _tmx_width=62
    [ "$_tmx_width" -lt 24 ] && _tmx_width=24

    printf '\033[H\033[J' >/dev/tty
    if [ "$_tmx_color" = 1 ]; then
      printf '\n  \033[1;38;5;81mtmux\033[0m \033[38;5;240m/\033[0m \033[1;38;5;213msession launcher\033[0m   \033[38;5;240m%s\033[0m\n  ' \
        "$_tmx_version" >/dev/tty
    else
      printf '\n  tmux / session launcher   %s\n  ' "$_tmx_version" >/dev/tty
    fi
    _tmux_launcher_rule "$_tmx_width" "$_tmx_color" >/dev/tty
    printf '\n' >/dev/tty

    awk -F'\t' -v W="$_tmx_width" -v sel="$_tmx_selected" -v pal="$_tmux_setup_palette" -v color="$_tmx_color" '
      BEGIN { esc = sprintf("%c", 27); np = split(pal, P, ","); si = 0 }
      {
        kind = $1; label = $3; detail = $4
        if (kind == "s")      { col = P[(si % np) + 1]; si++ }
        else if (kind == "n") { col = 114 }
        else                  { col = 245 }

        mark = (NR == sel) ? " > " : "   "
        body = mark label
        fill = W - length(body) - length(detail) - 1
        if (fill < 1) { detail = ""; fill = W - length(body); if (fill < 1) fill = 1 }
        sp = ""; for (i = 0; i < fill; i++) sp = sp " "

        if (color != "1") {
          if (NR == sel) print "  " esc "[7m" body sp detail " " esc "[0m"
          else           print "  " body sp detail " "
          next
        }
        if (NR == sel)
          print "  " esc "[1;38;5;16;48;5;" col "m" body sp detail " " esc "[0m"
        else
          print "  " esc "[38;5;" col "m" mark esc "[0m" esc "[1;38;5;" col "m" label esc "[0m" \
                sp esc "[38;5;240m" detail esc "[0m" " "
      }
    ' "$_tmx_tmp" >/dev/tty

    printf '\n  ' >/dev/tty
    _tmux_launcher_rule "$_tmx_width" "$_tmx_color" >/dev/tty
    if [ "$_tmx_color" = 1 ]; then
      printf '  \033[38;5;81mup/down\033[0m\033[38;5;240m|\033[0m\033[38;5;81mj/k\033[0m \033[38;5;245mmove\033[0m   \033[38;5;114menter\033[0m \033[38;5;245mselect\033[0m   \033[38;5;179mq\033[0m\033[38;5;240m/\033[0m\033[38;5;179mesc\033[0m \033[38;5;245mnative shell\033[0m\n' >/dev/tty
    else
      printf '  up/down or j/k move   enter select   q/esc native shell\n' >/dev/tty
    fi
  }

  trap '_tmux_launcher_keyboard_cleanup' 0
  trap 'exit 130' HUP INT TERM
  stty -icanon -echo min 1 time 0 </dev/tty
  printf '\033[?1049h\033[?25l' >/dev/tty

  while :; do
    _tmux_launcher_draw

    _tmx_key=$(dd bs=1 count=1 </dev/tty 2>/dev/null) || exit 1
    case $_tmx_key in
      "")
        awk -F'\t' -v n="$_tmx_selected" 'NR == n { print $2; exit }' "$_tmx_tmp"
        exit 0
        ;;
      q|Q)
        printf '%s\n' '[native shell]'
        exit 0
        ;;
      j)
        [ "$_tmx_selected" -lt "$_tmx_count" ] && _tmx_selected=$((_tmx_selected + 1))
        ;;
      k)
        [ "$_tmx_selected" -gt 1 ] && _tmx_selected=$((_tmx_selected - 1))
        ;;
      g)
        _tmx_selected=1
        ;;
      G)
        _tmx_selected=$_tmx_count
        ;;
      "$_tmx_escape")
        stty min 0 time 2 </dev/tty
        _tmx_key_1=$(dd bs=1 count=1 </dev/tty 2>/dev/null) || _tmx_key_1=""
        _tmx_key_2=""
        if [ "$_tmx_key_1" = ']' ]; then
          _tmux_launcher_discard_osc
          stty min 1 time 0 </dev/tty
          continue
        fi
        [ "$_tmx_key_1" = '[' ] && _tmx_key_2=$(dd bs=1 count=1 </dev/tty 2>/dev/null || printf '')
        if [ "$_tmx_key_1" = '[' ] && [ "$_tmx_key_2" != A ] && [ "$_tmx_key_2" != B ]; then
          _tmux_launcher_discard_csi
          stty min 1 time 0 </dev/tty
          continue
        fi
        stty min 1 time 0 </dev/tty
        case $_tmx_key_1:$_tmx_key_2 in
          '[:A') [ "$_tmx_selected" -gt 1 ] && _tmx_selected=$((_tmx_selected - 1)) ;;
          '[:B') [ "$_tmx_selected" -lt "$_tmx_count" ] && _tmx_selected=$((_tmx_selected + 1)) ;;
          *) printf '%s\n' '[native shell]'; exit 0 ;;
        esac
        ;;
    esac
  done
)

_tmux_launcher_keyboard_menu() {
  _tmx_choice=$(_tmux_launcher_keyboard_select "$1") || return 0
  case $_tmx_choice in
    ""|"[native shell]") return 0 ;;
    "[new session]") _tmux_launcher_new_session ;;
    *) _tmux_launcher_attach_or_create "$_tmx_choice" ;;
  esac
}

tmux_launcher() {
  command -v tmux >/dev/null 2>&1 || return 0
  _tmux_launcher_interactive_tty || return 0
  _tmux_launcher_in_tmux && return 0
  case ${TERM:-} in
    ""|dumb) return 0 ;;
  esac

  _tmux_setup_check_update

  _tmx_sessions=$(_tmux_launcher_sessions)

  _tmux_launcher_keyboard_menu "$_tmx_sessions"
}

# ---------------------------------------------------------------------------
# commands
# ---------------------------------------------------------------------------

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

# Manual update: runs the install.sh published on GitHub.
txu() {
  _tmx_setup_current=$(_tmux_setup_installed_version)
  _tmx_setup_latest=$(TMUX_SETUP_UPDATE_TIMEOUT=10 _tmux_setup_latest_version)
  if [ -z "$_tmx_setup_latest" ]; then
    _tmux_setup_say err 'Could not read the GitHub version; check curl and network'
    return 1
  fi
  _tmux_setup_touch_check
  printf 'local  %s\nlatest %s\n' "$_tmx_setup_current" "$_tmx_setup_latest"

  if _tmux_setup_version_gt "$_tmx_setup_latest" "$_tmx_setup_current"; then
    _tmux_setup_run_update "$_tmx_setup_latest"
    return $?
  fi
  case ${1:-} in
    -f|--force)
      _tmux_setup_say info 'Reinstalling the latest version'
      _tmux_setup_run_update "$_tmx_setup_latest"
      return $?
      ;;
  esac
  _tmux_setup_say ok 'Already up to date (force reinstall: txu -f)'
}

txv() {
  printf 'tmux-setup %s\n' "$(_tmux_setup_installed_version)"
  printf 'tmux       %s\n' "$(tmux -V 2>/dev/null || printf 'not installed')"
  if [ "${TMUX_SETUP_AUTO_UPDATE:-1}" = "0" ]; then
    printf 'auto update off\n'
  else
    printf 'auto update on (every %ss)\n' "${TMUX_SETUP_UPDATE_INTERVAL:-21600}"
  fi
  _tmx_setup_sums="$(_tmux_setup_state_dir)/managed.sums"
  [ -f "$_tmx_setup_sums" ] || return 0
  _tmux_setup_report_edit conf     "$(_tmux_setup_config_dir)/personal.tmux.conf" \
    'personal.tmux.conf is edited; updates keep your copy and write personal.tmux.conf.new'
  _tmux_setup_report_edit launcher "$(_tmux_setup_launcher_dir)/launcher.sh" \
    'launcher.sh is edited; updates back it up as launcher.sh.bak.<stamp> and replace it (put overrides in local.sh)'
}

_tmux_setup_report_edit() {
  _tmx_setup_key=$1
  _tmx_setup_path=$2
  _tmx_setup_note=$3
  _tmx_setup_recorded=$(awk -v k="$_tmx_setup_key" '$1 == k { print $2; exit }' \
    "$(_tmux_setup_state_dir)/managed.sums" 2>/dev/null)
  [ -n "$_tmx_setup_recorded" ] || return 0
  [ -f "$_tmx_setup_path" ] || return 0
  if command -v shasum >/dev/null 2>&1; then
    _tmx_setup_now=$(shasum -a 256 "$_tmx_setup_path" 2>/dev/null | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    _tmx_setup_now=$(sha256sum "$_tmx_setup_path" 2>/dev/null | awk '{print $1}')
  else
    return 0
  fi
  [ "$_tmx_setup_now" = "$_tmx_setup_recorded" ] || _tmux_setup_say warn "$_tmx_setup_note"
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

# ---------------------------------------------------------------------------
# user overlay: never created or overwritten by an update
# ---------------------------------------------------------------------------

if [ -f "$(_tmux_setup_launcher_dir)/local.sh" ]; then
  . "$(_tmux_setup_launcher_dir)/local.sh"
fi
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

remove_block() {
  local target="$1"
  local begin="$2"
  local end="$3"
  local tmp_file

  [[ -f "$target" ]] || return 0
  grep -Fq "$begin" "$target" || return 0

  tmp_file="$(mktemp)"
  awk -v begin="$begin" -v end="$end" '
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
  ' "$target" >"$tmp_file"
  install -m 0644 "$tmp_file" "$target"
  rm -f "$tmp_file"
}

# Blocks written by older or hand-rolled installs, so a shell never runs two
# launchers at once.
remove_legacy_shell_launcher_blocks() {
  local shell_conf entry begin end

  for shell_conf in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
    for entry in "${LEGACY_LAUNCHER_MARKERS[@]}"; do
      begin="${entry%%|*}"
      end="${entry##*|}"
      remove_block "$shell_conf" "$begin" "$end"
    done
  done
}

write_local_managed_block() {
  local tmux_conf="$1"
  local local_conf="$2"
  local quiet_source="$3"
  local block_file tmp_file quoted source_command

  quoted="$(tmux_quote "$local_conf")"
  if [[ "$quiet_source" -eq 1 ]]; then
    source_command="source-file -q"
  else
    source_command="source-file"
  fi

  block_file="$(mktemp)"
  tmp_file="$(mktemp)"

  {
    printf '%s\n' "$LOCAL_MARKER_BEGIN"
    printf '# Personal settings, loaded last. Updates never touch this block target.\n'
    printf '%s "%s"\n' "$source_command" "$quoted"
    printf '%s\n' "$LOCAL_MARKER_END"
  } >"$block_file"

  if [[ -f "$tmux_conf" ]] && grep -Fq "$LOCAL_MARKER_BEGIN" "$tmux_conf"; then
    awk -v begin="$LOCAL_MARKER_BEGIN" -v end="$LOCAL_MARKER_END" -v block_file="$block_file" '
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
  remove_block "$1" "$MARKER_BEGIN" "$MARKER_END"
}

remove_shell_launcher_block() {
  remove_block "$1" "$LAUNCHER_MARKER_BEGIN" "$LAUNCHER_MARKER_END"
}

remove_shell_launcher_blocks() {
  remove_shell_launcher_block "${HOME}/.zshrc"
  remove_shell_launcher_block "${HOME}/.bashrc"
}

main() {
  local skip_package_install=0
  local install_shell_launcher=1
  local check_updates=1
  local assume_yes=0
  local show_version=0
  local uninstall=0
  local config_home state_dir config_dir launcher_dir managed_conf launcher_file version_file tmux_conf installed_version supports_popup default_shell
  local local_conf local_launcher sums_file shell_flag_file supports_quiet_source launcher_backup config_backup

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --skip-package-install)
        skip_package_install=1
        ;;
      --no-shell-launcher)
        install_shell_launcher=0
        ;;
      --no-update-check)
        check_updates=0
        ;;
      -y|--yes)
        assume_yes=1
        ;;
      --version)
        show_version=1
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
  state_dir="${config_home}/${PROJECT_NAME}"
  config_dir="${config_home}/tmux"
  launcher_dir="${config_home}/tmux-launcher"
  managed_conf="${config_dir}/${CONFIG_NAME}"
  launcher_file="${launcher_dir}/${LAUNCHER_NAME}"
  version_file="${state_dir}/version"
  tmux_conf="${HOME}/.tmux.conf"
  local_conf="${config_dir}/${LOCAL_CONFIG_NAME}"
  local_launcher="${launcher_dir}/${LOCAL_LAUNCHER_NAME}"
  sums_file="${state_dir}/${SUMS_NAME}"
  shell_flag_file="${state_dir}/${SHELL_FLAG_NAME}"

  if [[ "$show_version" -eq 1 ]]; then
    info "tmux-setup local: $(installed_version "$version_file")"
    info "tmux-setup latest: $(latest_github_version)"
    info "tmux-setup bundled: ${INSTALLER_VERSION}"
    return
  fi

  if [[ "$uninstall" -eq 1 ]]; then
    remove_managed_block "$tmux_conf"
    remove_block "$tmux_conf" "$LOCAL_MARKER_BEGIN" "$LOCAL_MARKER_END"
    remove_shell_launcher_blocks
    remove_legacy_shell_launcher_blocks
    rm -f "$managed_conf"
    rm -f "${managed_conf}.new"
    rm -f "$launcher_file"
    rm -f "$version_file"
    rm -f "$sums_file"
    rm -f "$shell_flag_file"
    rm -f "${state_dir}/last-update-check"
    rmdir "$launcher_dir" 2>/dev/null || true
    rmdir "$state_dir" 2>/dev/null || true
    info "Removed managed tmux setup"
    if [[ -f "$local_conf" || -f "$local_launcher" ]]; then
      info "Kept your personal overlays:"
      [[ -f "$local_conf" ]] && info "  ${local_conf}"
      [[ -f "$local_launcher" ]] && info "  ${local_launcher}"
    fi
    return
  fi

  if [[ "$check_updates" -eq 1 ]]; then
    version_prompt "$version_file" "$assume_yes"
  fi

  install_tmux_package "$skip_package_install"

  installed_version="$(tmux_version)"
  supports_popup=0
  if version_at_least "$installed_version" "3.2"; then
    supports_popup=1
  else
    info "tmux ${installed_version} does not support display-popup; using built-in list-keys"
  fi

  default_shell="$(resolve_default_shell)"

  supports_quiet_source=0
  if version_at_least "$installed_version" "3.0"; then
    supports_quiet_source=1
  fi

  install -d -m 0755 "$state_dir"
  install -d -m 0755 "$config_dir"
  install -d -m 0755 "$launcher_dir"

  # Installs from before checksums were recorded cannot be inspected, so keep a
  # copy of whatever is there before replacing it.
  if [[ ! -f "$sums_file" && -f "$managed_conf" ]]; then
    config_backup="${managed_conf}.bak.$(date +%Y%m%d_%H%M%S)"
    cp -p "$managed_conf" "$config_backup"
    info "Backed up the previous config to ${config_backup}"
  fi

  # Never discard a hand-edited managed config: keep the user copy and put the
  # new defaults next to it instead.
  if user_edited conf "$managed_conf" "$sums_file"; then
    write_tmux_config "${managed_conf}.new" "$supports_popup" "$default_shell"
    if cmp -s "${managed_conf}.new" "$managed_conf"; then
      rm -f "${managed_conf}.new"
    else
      info "Kept your edited ${managed_conf}"
      info "New defaults written to ${managed_conf}.new"
      info "Personal settings belong in ${local_conf}; updates never touch it"
    fi
  else
    write_tmux_config "$managed_conf" "$supports_popup" "$default_shell"
    rm -f "${managed_conf}.new"
  fi

  if user_edited launcher "$launcher_file" "$sums_file"; then
    launcher_backup="${launcher_file}.bak.$(date +%Y%m%d_%H%M%S)"
    cp -p "$launcher_file" "$launcher_backup"
    info "Backed up your edited launcher.sh to ${launcher_backup}"
    info "Shell overrides belong in ${local_launcher}; updates never touch it"
  fi
  write_launcher_script "$launcher_file"

  write_local_launcher_stub "$local_launcher"
  write_local_tmux_conf_stub "$local_conf"
  write_managed_block "$tmux_conf" "$managed_conf"
  write_local_managed_block "$tmux_conf" "$local_conf" "$supports_quiet_source"

  # Older and hand-rolled installs left their own launcher blocks behind.
  remove_legacy_shell_launcher_blocks
  if [[ "$install_shell_launcher" -eq 1 ]]; then
    install_shell_launcher_blocks
  else
    remove_shell_launcher_blocks
  fi
  printf '%s\n' "$install_shell_launcher" >"$shell_flag_file"
  printf '%s\n' "$INSTALLER_VERSION" >"$version_file"
  record_sums "$sums_file" "$managed_conf" "$launcher_file"

  if [[ -n "${TMUX:-}" ]]; then
    tmux source-file "$tmux_conf"
    info "Reloaded active tmux session"
  fi

  info "Installed tmux setup version: ${INSTALLER_VERSION}"
  info "Installed tmux config: ${managed_conf}"
  info "Installed tmux launcher: ${launcher_file}"
  info "Personal overlays: ${local_conf}, ${local_launcher}"
  info "Prefix key: Ctrl+B"
  info "Shell session list: open a new interactive shell, or run tx"
  info "Key bindings screen: Ctrl+B then ?"
  info "Update: automatic on login, or run txu"
}

main "$@"
