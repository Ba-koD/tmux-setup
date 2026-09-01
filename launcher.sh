# shellcheck shell=sh

_tmux_setup_version="v0.5.2"
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
    ok)   _tmx_setup_hue=32 ;;
    warn) _tmx_setup_hue=33 ;;
    err)  _tmx_setup_hue=31 ;;
    *)    _tmx_setup_hue=36 ;;
  esac
  if _tmux_setup_use_color; then
    printf '\033[%sm%s\033[0m\n' "$_tmx_setup_hue" "$2"
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
    printf '\033[1mtmux-setup\033[0m \033[90m%s -> \033[0m\033[1;36m%s\033[0m\n' \
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

# tmux octal-escapes a session name that is not valid UTF-8, so refuse it here.
_tmux_launcher_name_ok() {
  case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) ;;
    *) return 0 ;;
  esac
  command -v iconv >/dev/null 2>&1 || return 0
  printf '%s' "$1" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1
}

_tmux_launcher_prompt_name() {
  while :; do
    if _tmux_setup_use_color; then
      printf '\033[1mNew tmux session name\033[0m \033[90m(empty or q to stay in the shell)\033[0m\n  \033[32m>\033[0m ' >&2
    else
      printf 'New tmux session name (empty/q to stay in shell): ' >&2
    fi
    IFS= read -r _tmx_name || return 1
    _tmx_trimmed=$(printf '%s' "$_tmx_name" | awk '{$1=$1; print}')
    case $_tmx_trimmed in
      ""|q|Q) return 1 ;;
    esac
    if _tmux_launcher_name_ok "$_tmx_name"; then
      printf '%s\n' "$_tmx_name"
      return 0
    fi
    _tmux_setup_say err 'That name is not valid text; type it again' >&2
  done
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
      printf '\n  \033[1mtmux session\033[0m \033[90m%s\033[0m\n\n' "$_tmx_version" >/dev/tty
    else
      printf '\n  tmux session %s\n\n' "$_tmx_version" >/dev/tty
    fi

    awk -F'\t' -v W="$_tmx_width" -v sel="$_tmx_selected" -v color="$_tmx_color" '
      BEGIN { esc = sprintf("%c", 27) }
      {
        kind = $1; label = $3; detail = $4
        if (kind == "s")      { dim = "36"; lit = "1;96" }
        else if (kind == "n") { dim = "32"; lit = "1;92" }
        else                  { dim = "90"; lit = "1;93" }

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
        col = (NR == sel) ? lit : dim
        print "  " esc "[" col "m" body esc "[0m" sp esc "[90m" detail esc "[0m" " "
      }
    ' "$_tmx_tmp" >/dev/tty

    if [ "$_tmx_color" = 1 ]; then
      printf '\n  \033[90mup/down or j/k move   enter select   q/esc native shell\033[0m\n' >/dev/tty
    else
      printf '\n  up/down or j/k move   enter select   q/esc native shell\n' >/dev/tty
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
        case $_tmx_key_1 in
          '[')
            _tmx_key_2=$(dd bs=1 count=1 </dev/tty 2>/dev/null || printf '')
            # A final byte ends the sequence; anything else still has bytes to come.
            case $_tmx_key_2 in
              [@-~]) ;;
              *) _tmux_launcher_discard_csi ;;
            esac
            ;;
          O)
            # SS3: the same cursor keys once the terminal is in application mode.
            _tmx_key_2=$(dd bs=1 count=1 </dev/tty 2>/dev/null || printf '')
            ;;
          ']')
            _tmux_launcher_discard_osc
            ;;
        esac
        stty min 1 time 0 </dev/tty
        case $_tmx_key_1:$_tmx_key_2 in
          '[:A'|'O:A') [ "$_tmx_selected" -gt 1 ] && _tmx_selected=$((_tmx_selected - 1)) ;;
          '[:B'|'O:B') [ "$_tmx_selected" -lt "$_tmx_count" ] && _tmx_selected=$((_tmx_selected + 1)) ;;
          ':') printf '%s\n' '[native shell]'; exit 0 ;;
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
