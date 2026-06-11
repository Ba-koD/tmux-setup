# shellcheck shell=sh

_tmux_setup_version="v0.4.1"
_tmux_setup_owner="Ba-koD"
_tmux_setup_repo="tmux-setup"

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

_tmux_setup_version_file() {
  printf '%s/tmux-setup/version\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
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

_tmux_setup_latest_version() {
  _tmx_setup_latest=""
  _tmx_setup_release_url="https://api.github.com/repos/${_tmux_setup_owner}/${_tmux_setup_repo}/releases/latest"
  _tmx_setup_tags_url="https://api.github.com/repos/${_tmux_setup_owner}/${_tmux_setup_repo}/tags"

  if command -v curl >/dev/null 2>&1; then
    _tmx_setup_latest=$(
      curl -fsSL -H 'Accept: application/vnd.github+json' "$_tmx_setup_release_url" 2>/dev/null |
        sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1
    ) || _tmx_setup_latest=""
    if [ -z "$_tmx_setup_latest" ]; then
      _tmx_setup_latest=$(
        curl -fsSL -H 'Accept: application/vnd.github+json' "$_tmx_setup_tags_url" 2>/dev/null |
          sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
          head -n 1
      ) || _tmx_setup_latest=""
    fi
  fi

  printf '%s\n' "${_tmx_setup_latest:-$_tmux_setup_version}"
}

_tmux_setup_prompt_update() {
  _tmx_setup_prompt=$1
  _tmx_setup_answer=""

  if ! { : </dev/tty >/dev/tty; } 2>/dev/null; then
    return 1
  fi

  printf '%s [y/N] ' "$_tmx_setup_prompt" >/dev/tty
  IFS= read -r _tmx_setup_answer </dev/tty || _tmx_setup_answer=""

  case $_tmx_setup_answer in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

_tmux_setup_run_update() {
  _tmx_setup_latest=$1
  _tmx_setup_url="https://github.com/${_tmux_setup_owner}/${_tmux_setup_repo}/raw/${_tmx_setup_latest}/install.sh"

  if ! command -v curl >/dev/null 2>&1; then
    printf 'tmux-setup update requires curl\n'
    return 0
  fi

  printf 'Updating tmux-setup to %s...\n' "$_tmx_setup_latest"
  curl -fsSL "$_tmx_setup_url" | bash -s -- --skip-package-install --yes --no-update-check
}

_tmux_setup_check_update() {
  [ -z "${NO_TMUX_UPDATE:-}" ] || return 0
  [ -z "${_TMUX_SETUP_UPDATE_CHECKED:-}" ] || return 0
  _tmux_launcher_interactive_tty || return 0
  _tmux_launcher_in_tmux && return 0

  _TMUX_SETUP_UPDATE_CHECKED=1
  export _TMUX_SETUP_UPDATE_CHECKED

  _tmx_setup_current=$(_tmux_setup_installed_version)
  _tmx_setup_latest=$(_tmux_setup_latest_version)

  if _tmux_setup_version_gt "$_tmx_setup_latest" "$_tmx_setup_current"; then
    printf 'tmux-setup local: %s\n' "$_tmx_setup_current"
    printf 'tmux-setup latest: %s\n' "$_tmx_setup_latest"
    if _tmux_setup_prompt_update "Update tmux-setup to ${_tmx_setup_latest} now?"; then
      _tmux_setup_run_update "$_tmx_setup_latest"
    else
      printf 'tmux-setup update skipped\n'
    fi
  fi
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

  _tmux_setup_check_update

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
