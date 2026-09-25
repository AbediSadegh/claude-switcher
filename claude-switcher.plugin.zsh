typeset -g _CLAUDE_SWITCHER_PLUGIN_FILE=${${(%):-%x}:A}

_claude_switcher_home() {
  emulate -L zsh
  print -r -- "${CLAUDE_SWITCHER_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-switcher}"
}

_claude_switcher_validate_profile() {
  emulate -L zsh
  local profile=${1:-}

  case "$profile" in
    ""|[!A-Za-z0-9]*|*[!A-Za-z0-9_-]*)
      print -u2 -- "Invalid profile '$profile'. Use letters, numbers, underscores, or hyphens."
      return 2
      ;;
  esac
}

_claude_switcher_profile_root() {
  emulate -L zsh
  print -r -- "$(_claude_switcher_home)/$1"
}

_claude_switcher_profile_exists() {
  emulate -L zsh
  local profile=$1

  [[ "$profile" == default || -d "$(_claude_switcher_profile_root "$profile")" ]]
}

_claude_switcher_prepare_profile() {
  emulate -L zsh
  local profile=$1
  local root=$(_claude_switcher_home)
  local profile_root=$(_claude_switcher_profile_root "$profile")

  [[ "$profile" == default ]] && return
  command mkdir -p -- "$profile_root/code" "$profile_root/desktop" || return
  command chmod 700 -- "$root" "$profile_root" "$profile_root/code" "$profile_root/desktop"
}

_claude_switcher_set_profile() {
  emulate -L zsh
  local profile=$1
  local root=$(_claude_switcher_home)
  local active_file="$root/.active-profile"

  _claude_switcher_validate_profile "$profile" || return
  _claude_switcher_profile_exists "$profile" || {
    print -u2 -- "Claude profile '$profile' does not exist. Run: claude-profile add $profile"
    return 1
  }
  _claude_switcher_prepare_profile "$profile" || return
  command mkdir -p -- "$root" || return
  command chmod 700 -- "$root" || return

  print -r -- "$profile" >| "$active_file" || return
  command chmod 600 -- "$active_file" || return
  typeset -gx CLAUDE_SWITCHER_PROFILE="$profile"
  print -r -- "Switched Claude profile to '$profile'."
}

_claude_switcher_add_profile() {
  emulate -L zsh
  local profile=$1

  _claude_switcher_validate_profile "$profile" || return
  [[ "$profile" != default ]] || {
    print -u2 -- "The default profile already exists and uses Claude's native directories."
    return 2
  }

  _claude_switcher_profile_exists "$profile" && {
    print -u2 -- "Claude profile '$profile' already exists."
    return 1
  }

  _claude_switcher_prepare_profile "$profile" || return
  print -r -- "Added Claude profile '$profile'."
}

_claude_switcher_confirm_removal() {
  emulate -L zsh
  local profile=$1
  local profile_root=$(_claude_switcher_profile_root "$profile")
  local reply

  [[ -t 0 ]] || {
    print -u2 -- "Refusing non-interactive removal. Re-run with --force."
    return 2
  }

  print -n -u2 -- "Remove Claude profile '$profile' and all data in '$profile_root'? [y/N] "
  IFS= read -r reply

  case "$reply" in
    y|Y|yes|Yes|YES)
      return
      ;;
    *)
      print -u2 -- "Removal cancelled."
      return 1
      ;;
  esac
}

_claude_switcher_remove_profile() {
  emulate -L zsh
  local profile=
  local force=0
  local argument
  local profile_root
  local active_file="$(_claude_switcher_home)/.active-profile"
  local persisted_profile=

  for argument in "$@"; do
    case "$argument" in
      -f|--force)
        force=1
        ;;
      -*)
        print -u2 -- "Unknown option: $argument"
        return 2
        ;;
      *)
        [[ -z "$profile" ]] || {
          print -u2 -- "Usage: claude-profile remove PROFILE [--force]"
          return 2
        }
        profile=$argument
        ;;
    esac
  done

  [[ -n "$profile" ]] || {
    print -u2 -- "Usage: claude-profile remove PROFILE [--force]"
    return 2
  }

  _claude_switcher_validate_profile "$profile" || return
  [[ "$profile" != default ]] || {
    print -u2 -- "The default profile cannot be removed."
    return 2
  }
  [[ "$profile" != "$CLAUDE_SWITCHER_PROFILE" ]] || {
    print -u2 -- "Cannot remove the active profile. Switch profiles first."
    return 2
  }
  _claude_switcher_profile_exists "$profile" || {
    print -u2 -- "Claude profile '$profile' does not exist."
    return 1
  }

  (( force )) || _claude_switcher_confirm_removal "$profile" || return

  profile_root=$(_claude_switcher_profile_root "$profile")
  command rm -rf -- "$profile_root" || return

  if [[ -r "$active_file" ]]; then
    IFS= read -r persisted_profile < "$active_file"
    if [[ "$persisted_profile" == "$profile" ]]; then
      print -r -- default >| "$active_file" || return
      command chmod 600 -- "$active_file" || return
    fi
  fi

  print -r -- "Removed Claude profile '$profile'."
}

_claude_switcher_load_profile() {
  emulate -L zsh
  local active_file="$(_claude_switcher_home)/.active-profile"
  local profile=${CLAUDE_SWITCHER_PROFILE:-}

  if [[ -z "$profile" && -r "$active_file" ]]; then
    IFS= read -r profile < "$active_file"
  fi

  if ! _claude_switcher_validate_profile "$profile" >/dev/null 2>&1 ||
    ! _claude_switcher_profile_exists "$profile"; then
    profile=${CLAUDE_SWITCHER_DEFAULT_PROFILE:-default}
  fi

  if ! _claude_switcher_validate_profile "$profile" >/dev/null 2>&1 ||
    ! _claude_switcher_profile_exists "$profile"; then
    profile=default
  fi

  typeset -gx CLAUDE_SWITCHER_PROFILE="$profile"
  _claude_switcher_prepare_profile "$profile"

  if [[ -z "$CLAUDE_SWITCHER_PROMPT_ENABLED" ]]; then
    if [[ -e "$(_claude_switcher_prompt_disable_path)" ]]; then
      typeset -g CLAUDE_SWITCHER_PROMPT_ENABLED=off
    else
      typeset -g CLAUDE_SWITCHER_PROMPT_ENABLED=on
    fi
  fi
}

_claude_switcher_desktop_binary() {
  emulate -L zsh
  local configured=${CLAUDE_DESKTOP_BIN:-}
  local candidate

  if [[ -n "$configured" ]]; then
    if [[ -x "$configured" ]]; then
      print -r -- "$configured"
      return
    fi

    candidate=$(whence -p -- "$configured") || return 1
    print -r -- "$candidate"
    return
  fi

  if [[ "$OSTYPE" == darwin* ]]; then
    for candidate in \
      "/Applications/Claude.app/Contents/MacOS/Claude" \
      "$HOME/Applications/Claude.app/Contents/MacOS/Claude"; do
      if [[ -x "$candidate" ]]; then
        print -r -- "$candidate"
        return
      fi
    done
  fi

  whence -p -- claude-desktop
}

_claude_switcher_desktop_data_dir() {
  emulate -L zsh
  local profile=$1

  if [[ "$profile" == default ]]; then
    print -r -- "${XDG_CONFIG_HOME:-$HOME/.config}/Claude"
  else
    print -r -- "$(_claude_switcher_profile_root "$profile")/desktop"
  fi
}

_claude_switcher_desktop_running() {
  emulate -L zsh
  local lock="$1/SingletonLock"
  local target
  local pid

  [[ -L "$lock" ]] || return 1
  target=$(command readlink -- "$lock") || return 1
  pid=${target##*-}
  [[ "$pid" == <-> ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

_claude_switcher_url_profile() {
  emulate -L zsh
  local root=$(_claude_switcher_home)
  local persisted=
  local profile
  local -a running
  local -a named=("$root"/*(N/:t))

  if [[ -r "$root/.active-profile" ]]; then
    IFS= read -r persisted < "$root/.active-profile"
  fi
  if ! _claude_switcher_validate_profile "$persisted" >/dev/null 2>&1 ||
    ! _claude_switcher_profile_exists "$persisted"; then
    persisted=default
  fi

  for profile in default "${(@)named:#default}"; do
    _claude_switcher_validate_profile "$profile" >/dev/null 2>&1 || continue
    _claude_switcher_desktop_running "$(_claude_switcher_desktop_data_dir "$profile")" &&
      running+=("$profile")
  done

  if (( ${running[(Ie)$persisted]} )); then
    print -r -- "$persisted"
  elif (( $#running == 1 )); then
    print -r -- "$running[1]"
  else
    print -r -- "$persisted"
  fi
}

_claude_switcher_open_url() {
  emulate -L zsh
  local -x CLAUDE_SWITCHER_PROFILE

  CLAUDE_SWITCHER_PROFILE=$(_claude_switcher_url_profile) || return
  claude-desktop "$@"
}

_claude_switcher_url_handler_paths() {
  emulate -L zsh
  local apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

  reply=(
    "$(_claude_switcher_home)/url-handler"
    "$apps_dir/claude-switcher-url-handler.desktop"
    "$(_claude_switcher_home)/.url-handler-previous"
  )
}

_claude_switcher_desktop_exec_quote() {
  emulate -L zsh
  local value=$1

  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//\`/\\\`}
  value=${value//\$/\\\$}
  value=${value//\\/\\\\}
  value=${value//\%/%%}
  print -r -- "\"$value\""
}

_claude_switcher_url_handler_install() {
  emulate -L zsh
  local root=$(_claude_switcher_home)
  local script desktop_file previous_file
  local zsh_binary
  local desktop_binary
  local previous
  local -a reply

  [[ "$OSTYPE" == linux* ]] || {
    print -u2 -- "The claude:// URL handler is only supported on Linux."
    return 1
  }
  zsh_binary=$(whence -p -- zsh) || {
    print -u2 -- "zsh executable not found in PATH."
    return 127
  }
  desktop_binary=$(_claude_switcher_desktop_binary) || {
    print -u2 -- "Claude Desktop executable not found. Set CLAUDE_DESKTOP_BIN."
    return 127
  }

  _claude_switcher_url_handler_paths
  script=$reply[1]
  desktop_file=$reply[2]
  previous_file=$reply[3]

  command mkdir -p -- "$root" "${desktop_file:h}" || return
  command chmod 700 -- "$root" || return

  print -r -- "#!$zsh_binary -f
unset CLAUDE_SWITCHER_PROFILE CLAUDE_SWITCHER_DEFAULT_PROFILE CLAUDE_CONFIG_DIR
export CLAUDE_SWITCHER_HOME=${(qq)root}
export CLAUDE_DESKTOP_BIN=${(qq)desktop_binary}
source ${(qq)_CLAUDE_SWITCHER_PLUGIN_FILE} || exit
_claude_switcher_open_url \"\$@\"" >| "$script" || return
  command chmod 700 -- "$script" || return

  print -r -- "[Desktop Entry]
Type=Application
Name=Claude (claude-switcher)
Comment=Open claude:// links in the matching claude-switcher profile
Exec=$(_claude_switcher_desktop_exec_quote "$script") %u
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/claude;" >| "$desktop_file" || return

  if (( $+commands[update-desktop-database] )); then
    command update-desktop-database -q -- "${desktop_file:h}" 2>/dev/null
  fi

  (( $+commands[xdg-mime] )) || {
    print -u2 -- "xdg-mime not found. Set ${desktop_file:t} as the default handler for x-scheme-handler/claude manually."
    return 1
  }

  previous=$(command xdg-mime query default x-scheme-handler/claude 2>/dev/null)
  if [[ -n "$previous" && "$previous" != "${desktop_file:t}" ]]; then
    print -r -- "$previous" >| "$previous_file" || return
  fi
  command xdg-mime default "${desktop_file:t}" x-scheme-handler/claude || return
  print -r -- "Installed claude:// URL handler '$desktop_file'."
}

_claude_switcher_url_handler_uninstall() {
  emulate -L zsh
  local script desktop_file previous_file
  local previous=
  local -a reply

  _claude_switcher_url_handler_paths
  script=$reply[1]
  desktop_file=$reply[2]
  previous_file=$reply[3]

  if [[ -r "$previous_file" ]]; then
    IFS= read -r previous < "$previous_file"
  fi
  if [[ -n "$previous" ]] && (( $+commands[xdg-mime] )); then
    command xdg-mime default "$previous" x-scheme-handler/claude || return
  fi

  command rm -f -- "$script" "$desktop_file" "$previous_file" || return
  if (( $+commands[update-desktop-database] )); then
    command update-desktop-database -q -- "${desktop_file:h}" 2>/dev/null
  fi
  print -r -- "Removed claude:// URL handler${previous:+, restored '$previous'}."
}

_claude_switcher_url_handler_status() {
  emulate -L zsh
  local current=
  local -a reply

  _claude_switcher_url_handler_paths
  if (( $+commands[xdg-mime] )); then
    current=$(command xdg-mime query default x-scheme-handler/claude 2>/dev/null)
  fi

  if [[ -e "$reply[2]" && "$current" == "${reply[2]:t}" ]]; then
    print -r -- "installed: claude:// links open in profile '$(_claude_switcher_url_profile)'"
  elif [[ -e "$reply[2]" ]]; then
    print -r -- "installed but not the default handler (current: ${current:-unknown})"
  else
    print -r -- "not installed (current handler: ${current:-unknown})"
  fi
}

_claude_switcher_url_handler() {
  emulate -L zsh

  case "${1:-status}" in
    install) _claude_switcher_url_handler_install ;;
    uninstall) _claude_switcher_url_handler_uninstall ;;
    status) _claude_switcher_url_handler_status ;;
    *)
      print -u2 -- "Usage: claude-profile url-handler [install | uninstall | status]"
      return 2
      ;;
  esac
}

claude-profile() {
  emulate -L zsh
  local action=${1:-}

  case "$action" in
    "")
      print -r -- "$CLAUDE_SWITCHER_PROFILE"
      ;;
    -l|--list|list)
      _claude_switcher_list_profiles
      ;;
    -h|--help|help)
      print -r -- "Usage:
  claude-profile
  claude-profile PROFILE
  claude-profile use PROFILE
  claude-profile add PROFILE
  claude-profile remove PROFILE [--force]
  claude-profile url-handler [install | uninstall | status]
  claude-profile --list
  claude-profile --current

See also: claudeon --help, claudeoff --help"
      ;;
    -c|--current|current)
      print -r -- "$CLAUDE_SWITCHER_PROFILE"
      ;;
    add)
      [[ $# == 2 ]] || {
        print -u2 -- "Usage: claude-profile add PROFILE"
        return 2
      }
      _claude_switcher_add_profile "$2"
      ;;
    remove)
      _claude_switcher_remove_profile "${@:2}"
      ;;
    use)
      [[ $# == 2 ]] || {
        print -u2 -- "Usage: claude-profile use PROFILE"
        return 2
      }
      _claude_switcher_set_profile "$2"
      ;;
    url-handler)
      [[ $# -le 2 ]] || {
        print -u2 -- "Usage: claude-profile url-handler [install | uninstall | status]"
        return 2
      }
      _claude_switcher_url_handler "${@:2}"
      ;;
    *)
      [[ $# == 1 ]] || {
        print -u2 -- "Usage: claude-profile PROFILE"
        return 2
      }
      _claude_switcher_set_profile "$action"
      ;;
  esac
}

_claude_switcher_list_profiles() {
  emulate -L zsh
  local root=$(_claude_switcher_home)
  local profile_dir
  local profile

  if [[ "$CLAUDE_SWITCHER_PROFILE" == default ]]; then
    print -r -- "* default"
  else
    print -r -- "  default"
  fi

  [[ -d "$root" ]] || return

  for profile_dir in "$root"/*(N/); do
    profile=${profile_dir:t}
    [[ "$profile" == default ]] && continue

    if [[ "$profile" == "$CLAUDE_SWITCHER_PROFILE" ]]; then
      print -r -- "* $profile"
    else
      print -r -- "  $profile"
    fi
  done
}

_claude_switcher_prompt_disable_path() {
  emulate -L zsh
  print -r -- "$(_claude_switcher_home)/.prompt-disabled"
}

_claude_switcher_prompt_usage() {
  emulate -L zsh
  print -r -- "Toggle the claude-switcher prompt segment

Usage: $1 [-g | --global] [-h | --help]

With no arguments, applies to this shell only.

  -g --global  persist the setting for new shells
  -h --help    print this message"
}

claudeon() {
  emulate -L zsh

  case "${1:-}" in
    -h|--help)
      _claude_switcher_prompt_usage claudeon
      return
      ;;
    -g|--global)
      command rm -f -- "$(_claude_switcher_prompt_disable_path)" || return
      ;;
    "") ;;
    *)
      print -u2 -- "Unknown option: $1"
      _claude_switcher_prompt_usage claudeon >&2
      return 2
      ;;
  esac

  typeset -g CLAUDE_SWITCHER_PROMPT_ENABLED=on
}

claudeoff() {
  emulate -L zsh
  local disable_path=$(_claude_switcher_prompt_disable_path)

  case "${1:-}" in
    -h|--help)
      _claude_switcher_prompt_usage claudeoff
      return
      ;;
    -g|--global)
      command mkdir -p -- "${disable_path:h}" || return
      command touch -- "$disable_path" || return
      ;;
    "") ;;
    *)
      print -u2 -- "Unknown option: $1"
      _claude_switcher_prompt_usage claudeoff >&2
      return 2
      ;;
  esac

  typeset -g CLAUDE_SWITCHER_PROMPT_ENABLED=off
}

claude_ps1() {
  emulate -L zsh
  local segment
  local symbol
  local prefix
  local separator
  local suffix

  [[ "$CLAUDE_SWITCHER_PROMPT_ENABLED" != off ]] || return
  [[ "$CLAUDE_SWITCHER_PROFILE" != default ||
    "$CLAUDE_SWITCHER_PROMPT_HIDE_IF_DEFAULT" != true ]] || return

  prefix=${CLAUDE_SWITCHER_PROMPT_PREFIX-(}
  separator=${CLAUDE_SWITCHER_PROMPT_SEPARATOR-|}
  suffix=${CLAUDE_SWITCHER_PROMPT_SUFFIX-)}
  symbol=${CLAUDE_SWITCHER_PROMPT_SYMBOL-$'✳'}

  segment=$prefix

  if [[ -n "$symbol" ]]; then
    segment+="%F{${CLAUDE_SWITCHER_PROMPT_SYMBOL_COLOR:-208}}$symbol%f$separator"
  fi

  segment+="%F{${CLAUDE_SWITCHER_PROMPT_PROFILE_COLOR:-cyan}}$CLAUDE_SWITCHER_PROFILE%f$suffix"

  print -nr -- "$segment"
}

_claude_switcher_completion() {
  emulate -L zsh
  local root=$(_claude_switcher_home)
  local -a commands
  local -a profiles
  local profile_dir
  local curcontext="$curcontext" state line

  commands=(
    'add:Add a named profile'
    'remove:Remove a named profile'
    'use:Switch profiles'
    'url-handler:Route claude:// links to the matching profile'
    'list:List profiles'
    'current:Show the active profile'
    'help:Show usage'
  )
  profiles=(default)

  for profile_dir in "$root"/*(N/); do
    [[ "${profile_dir:t}" == default ]] || profiles+=("${profile_dir:t}")
  done

  _arguments -C \
    '1: :->command' \
    '*:: :->args'

  case "$state" in
    command)
      _describe -t commands command commands
      _describe -t profiles profile profiles
      ;;
    args)
      case "$line[1]" in
        add)
          _message "new profile name"
          ;;
        use)
          _arguments "1:profile:($profiles)"
          ;;
        url-handler)
          _arguments '1:action:(install uninstall status)'
          ;;
        remove)
          _arguments \
            '(-f --force)'{-f,--force}'[remove without confirmation]' \
            "1:profile:($profiles)"
          ;;
      esac
      ;;
  esac
}

claude() {
  emulate -L zsh
  local binary
  local code_dir="$(_claude_switcher_home)/$CLAUDE_SWITCHER_PROFILE/code"

  binary=$(whence -p -- claude) || {
    print -u2 -- "Claude Code executable not found in PATH."
    return 127
  }

  if [[ "$CLAUDE_SWITCHER_PROFILE" == default ]]; then
    (
      unset CLAUDE_CONFIG_DIR
      "$binary" "$@"
    )
    return
  fi

  _claude_switcher_profile_exists "$CLAUDE_SWITCHER_PROFILE" || {
    print -u2 -- "Active Claude profile '$CLAUDE_SWITCHER_PROFILE' no longer exists."
    return 1
  }
  _claude_switcher_prepare_profile "$CLAUDE_SWITCHER_PROFILE" || return
  CLAUDE_CONFIG_DIR="$code_dir" "$binary" "$@"
}

claude-desktop() {
  emulate -L zsh
  local binary
  local profile_root="$(_claude_switcher_home)/$CLAUDE_SWITCHER_PROFILE"
  local code_dir="$profile_root/code"
  local desktop_dir="$profile_root/desktop"

  binary=$(_claude_switcher_desktop_binary) || {
    print -u2 -- "Claude Desktop executable not found. Set CLAUDE_DESKTOP_BIN."
    return 127
  }

  if [[ "$CLAUDE_SWITCHER_PROFILE" == default ]]; then
    (
      unset CLAUDE_CONFIG_DIR
      "$binary" "$@"
    ) &!
    print -r -- "Started Claude Desktop default profile (PID $!)."
    return
  fi

  _claude_switcher_profile_exists "$CLAUDE_SWITCHER_PROFILE" || {
    print -u2 -- "Active Claude profile '$CLAUDE_SWITCHER_PROFILE' no longer exists."
    return 1
  }
  _claude_switcher_prepare_profile "$CLAUDE_SWITCHER_PROFILE" || return
  CLAUDE_CONFIG_DIR="$code_dir" "$binary" "--user-data-dir=$desktop_dir" "$@" &!
  print -r -- "Started Claude Desktop profile '$CLAUDE_SWITCHER_PROFILE' (PID $!)."
}

_claude_switcher_load_profile

if (( $+functions[compdef] )); then
  compdef _claude_switcher_completion claude-profile
fi
