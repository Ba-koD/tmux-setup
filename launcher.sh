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

_tmux_launcher_keyboard_select() (
  _tmx_sessions=$1
  _tmx_tmp=$(_tmux_launcher_mktemp) || return 1
  {
    [ -n "$_tmx_sessions" ] && printf '%s\n' "$_tmx_sessions"
    printf '%s\n' '[new session]' '[native shell]'
  } >"$_tmx_tmp"
  _tmx_count=$(awk 'END { print NR + 0 }' "$_tmx_tmp")
  _tmx_selected=1
  _tmx_escape=$(printf '\033')

  _tmx_tty_state=$(stty -g </dev/tty) || {
    rm -f "$_tmx_tmp"
    return 1
  }
  _tmux_launcher_keyboard_cleanup() {
    stty "$_tmx_tty_state" </dev/tty 2>/dev/null || :
    printf '\033[?1049l' >/dev/tty
    rm -f "$_tmx_tmp"
  }
  trap '_tmux_launcher_keyboard_cleanup' 0
  trap 'exit 130' HUP INT TERM
  stty -icanon -echo min 1 time 0 </dev/tty
  printf '\033[?1049h' >/dev/tty

  while :; do
    printf '\033[H\033[Jtmux session\n\n' >/dev/tty
    awk -v selected="$_tmx_selected" '
      BEGIN { esc = sprintf("%c", 27) }
      NR == selected { printf "%s[7m> %s%s[0m\n", esc, $0, esc; next }
      { printf "  %s\n", $0 }
    ' "$_tmx_tmp" >/dev/tty

    _tmx_key=$(dd bs=1 count=1 </dev/tty 2>/dev/null) || exit 1
    case $_tmx_key in
      "")
        awk -v n="$_tmx_selected" 'NR == n { print; exit }' "$_tmx_tmp"
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
      "$_tmx_escape")
        stty min 0 time 2 </dev/tty
        _tmx_key_1=$(dd bs=1 count=1 </dev/tty 2>/dev/null) || _tmx_key_1=""
        _tmx_key_2=""
        [ "$_tmx_key_1" = '[' ] && _tmx_key_2=$(dd bs=1 count=1 </dev/tty 2>/dev/null || printf '')
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
