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

claude-profile() {
  emulate -L zsh
  local action=${1:-}

  case "$action" in
    "")
      print -r -- "$CLAUDE_SWITCHER_PROFILE"
      ;;
    -l|--list|list)
      claude-profiles
      ;;
    -h|--help|help)
      print -r -- "Usage:
  claude-profile
  claude-profile PROFILE
  claude-profile use PROFILE
  claude-profile add PROFILE
  claude-profile remove PROFILE [--force]
  claude-profile --list
  claude-profile --current

See also: claude-profiles --help, claudeon --help, claudeoff --help"
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
    *)
      [[ $# == 1 ]] || {
        print -u2 -- "Usage: claude-profile PROFILE"
        return 2
      }
      _claude_switcher_set_profile "$action"
      ;;
  esac
}

claude-profiles() {
  emulate -L zsh
  local root=$(_claude_switcher_home)
  local profile_dir
  local profile

  case "${1:-}" in
    -h|--help)
      print -r -- "List Claude profiles, marking the active one with '*'.

Usage: claude-profiles"
      return
      ;;
    "") ;;
    *)
      print -u2 -- "Unknown option: $1"
      return 2
      ;;
  esac

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
