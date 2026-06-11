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
