# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file zsh plugin (`claude-switcher.plugin.zsh`) that gives Claude Code and Claude Desktop named, isolated account profiles — separate `CLAUDE_CONFIG_DIR` / Electron `--user-data-dir` per profile, switchable per-shell. There is no build step, package manifest, or test suite; the entire implementation is the one `.zsh` file, documented in `README.md`.

## Verifying changes

There is no test harness — verify behavior by sourcing the plugin in an isolated `zsh -f` process and exercising the functions directly. Always redirect `CLAUDE_SWITCHER_HOME` to a scratch directory first so runs don't touch the real profile store at `${XDG_DATA_HOME:-$HOME/.local/share}/claude-switcher`:

```zsh
export CLAUDE_SWITCHER_HOME=/tmp/scratch-claude-switcher
rm -rf "$CLAUDE_SWITCHER_HOME"
zsh -f -c 'source /path/to/claude-switcher.plugin.zsh; claude-profile add work; claude-profile use work; claude-profile'
```

`zsh -f` skips the user's own `.zshrc`/`.zshenv`, so ambient aliases, functions, and env vars (proxy vars in particular) don't leak into the test. To exercise the oh-my-zsh completion path, source through `$ZSH/oh-my-zsh.sh` with `ZSH_CUSTOM` pointed at a scratch plugin directory rather than sourcing the plugin file directly — `compdef` registration and plugin discovery only happen through that loader (see the Install section of README.md).

`claude` and `claude-desktop` shell out to real binaries; stub them with a `bin/claude` script on `PATH` ahead of the real one when testing the wrapper logic (env vars, `CLAUDE_CONFIG_DIR`, argument forwarding) without needing the actual CLI or Electron app installed.

## Architecture

**Everything is a `zsh` function, no external state beyond one directory.** All profile data lives under `_claude_switcher_home` (`$CLAUDE_SWITCHER_HOME`, defaulting to `${XDG_DATA_HOME:-$HOME/.local/share}/claude-switcher`). Each named profile is a subdirectory with `code/` and `desktop/` subdirs (owner-only permissions, `chmod 700`); the built-in `default` profile has no directory and deliberately uses Claude's native config/data locations unmodified.

**Profile selection has two layers that must stay in sync:** `CLAUDE_SWITCHER_PROFILE` (a `typeset -gx` shell-local variable, exported so subshells/children inherit it) is the active profile for the *current* shell; `$CLAUDE_SWITCHER_HOME/.active-profile` is the persisted default for *new* shells. `_claude_switcher_set_profile` writes both. `_claude_switcher_load_profile` (called once at plugin-source time, `claude-switcher.plugin.zsh:512`) reads the persisted file only if `CLAUDE_SWITCHER_PROFILE` isn't already set — this is what lets two terminals run different profiles simultaneously without one clobbering the other's persisted default.

**The `claude` and `claude-desktop` wrapper functions shadow the real binaries by name.** They resolve the actual executable via `whence -p`/`_claude_switcher_desktop_binary` (which never reads its own function definition, avoiding self-recursion), then branch on whether the active profile is `default`: for `default` they explicitly `unset CLAUDE_CONFIG_DIR` in a subshell so no plugin state leaks through; for named profiles they set `CLAUDE_CONFIG_DIR` (and, for Desktop, `--user-data-dir`) to the profile's directories. Anything appended after `claude`/`claude-desktop` on the command line — including proxy env prefixes from shell aliases — passes straight through, since zsh expands an alias's assignment prefix onto the function call itself rather than intercepting it.

**Every mutating operation validates the profile name first** (`_claude_switcher_validate_profile`: letters/digits/underscore/hyphen only) before touching the filesystem, and profile removal requires either an interactive `y` confirmation or an explicit `--force` flag for non-interactive callers.

**The prompt segment (`claude_ps1`) is decoupled from profile switching.** It reads `CLAUDE_SWITCHER_PROMPT_ENABLED` (shell-local, seeded at load time from a `.prompt-disabled` marker file under `CLAUDE_SWITCHER_HOME`) and a set of `CLAUDE_SWITCHER_PROMPT_*` variables for styling — mirroring the kube-ps1 `kubeon`/`kubeoff` on/off pattern, including the `-g`/`--global` split between "this shell" and "persisted for new shells."

**Zsh-specific conventions used throughout, worth preserving in new code:**
- Every function opens with `emulate -L zsh` for local, predictable option scoping.
- Internal helpers are prefixed `_claude_switcher_*` and not meant to be called directly by users; user-facing commands (`claude-profile`, `claude-profiles`, `claudeon`, `claudeoff`, `claude`, `claude-desktop`, `claude_ps1`) are unprefixed.
- Filesystem-mutating calls use `command mkdir`/`command rm`/`command chmod` etc. to bypass any user-defined aliases for those builtins.
- `-h`/`--help` is implemented per-command (see `claude-profile`, `claude-profiles`, `claudeon`, `claudeoff`) rather than centrally; `claude` and `claude-desktop` deliberately do *not* intercept `--help` so it passes through to the real CLI's own help.
- Completion (`_claude_switcher_completion`, registered via `compdef` only if available) must be kept in sync by hand with `claude-profile`'s subcommand list — there's no single source of truth generating both.
