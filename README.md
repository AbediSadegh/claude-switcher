# claude-switcher

A zsh plugin with an active Claude account profile for Claude Code and Claude Desktop.

## Scope: per-shell, not global

Profile **data** — the `code`/`desktop` directories under `$CLAUDE_SWITCHER_HOME` — is global: one shared store on disk, visible to every shell and session on the machine. Adding or removing a profile in one terminal is immediately visible in all others.

Which profile is **active** is per-shell. `claude-profile work` changes only the current shell (and any child process or subshell it starts, since the setting is exported to the environment) — other already-open terminals keep whatever profile they had active. This is what lets two terminals run `claude` against different accounts at the same time.

New shells don't inherit from whichever terminal you last touched — they start from one persisted default at `$CLAUDE_SWITCHER_HOME/.active-profile`, updated every time any shell switches profiles. Set `CLAUDE_SWITCHER_DEFAULT_PROFILE` before sourcing the plugin to override the starting profile for one shell without touching that persisted default.

The prompt toggle (`claudeon`/`claudeoff`) follows the same split — see [Prompt](#prompt).

## Install

### oh-my-zsh

Link the checkout into the custom plugin directory. The directory name must match the plugin file, so keep it `claude-switcher`:

```zsh
ln -s /path/to/claude-switcher "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/claude-switcher"
```

Add it to the plugin list in `.zshrc`:

```zsh
plugins=(... claude-switcher)
```

oh-my-zsh sources plugins after `compinit`, so tab completion for `claude-profile` registers on its own.

### Plain zsh

Source the plugin from `.zshrc`, after `compinit` if you want completion:

```zsh
source /path/to/claude-switcher/claude-switcher.plugin.zsh
```

### Prompt segment

Add `claude_ps1` to the prompt in `.zshrc`, after the plugin is loaded:

```zsh
setopt prompt_subst
PROMPT='$(claude_ps1) '"$PROMPT"
```

Themes that place segments explicitly call `claude_ps1` alongside the others instead. Escape the `$` so it is evaluated on each prompt rather than once at theme load:

```zsh
PROMPT="... \$(kube_ps1) \$(claude_ps1) ..."
```

### Reload

```zsh
exec zsh
```

## Usage

Create and select a named profile:

```zsh
claude-profile add personal
claude-profile personal
```

`claude-profile use personal` is the explicit form of the same switch.

Then use the normal commands:

```zsh
claude
claude-desktop
```

Switch profiles:

```zsh
claude-profile add work
claude-profile work
```

Inspect profiles:

```zsh
claude-profile
claude-profile --list
```

Remove an unused profile:

```zsh
claude-profile default
claude-profile remove work
```

Removal deletes the profile's Code and Desktop data after confirmation. Scripts and other non-interactive sessions must explicitly use `--force`:

```zsh
claude-profile remove work --force
```

The built-in `default` profile cannot be added or removed. An active profile cannot be removed; switch to another profile first. Named profile directories use owner-only permissions.

The built-in `default` profile uses Claude's native configuration and data directories without setting `CLAUDE_CONFIG_DIR` or `--user-data-dir`:

```zsh
claude-profile default
```

Two terminals can run different accounts at once, since the active profile is per-shell (see [Scope](#scope-per-shell-not-global)):

```zsh
# Terminal 1
claude-profile add personal
claude-profile personal
claude

# Terminal 2
claude-profile add work
claude-profile work
claude
```

Named profiles store their files under:

```text
${CLAUDE_SWITCHER_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-switcher}/<profile>/
├── code/
└── desktop/
```

Claude Code and Claude Desktop share each named profile's `code` directory. Desktop cookies and application data remain isolated in `desktop`.

Each named profile requires authentication on first use. Claude Desktop support uses Electron's `--user-data-dir` isolation on Linux and macOS. Set `CLAUDE_DESKTOP_BIN` when the executable is not auto-detected:

```zsh
export CLAUDE_DESKTOP_BIN=/path/to/claude-desktop
```

### `claude://` links

Links such as `claude://claude.ai/customize/connectors/...` (sent by the browser after connecting an integration or signing in) are opened by the desktop environment, not by your shell, so the `claude-desktop` function never runs. The default handler therefore delivers them to the `default` profile's Desktop instance. On Linux, install a handler that routes them to the right profile instead:

```zsh
claude-profile url-handler install
claude-profile url-handler status
```

A link goes to the persisted active profile (`$CLAUDE_SWITCHER_HOME/.active-profile`) if its Desktop instance is running. Otherwise it goes to whichever profile's Desktop instance is running, if exactly one is. Otherwise it starts the persisted active profile. Re-run `install` after moving the plugin checkout or the Desktop binary, since both paths are recorded in the generated handler. `claude-profile url-handler uninstall` removes the handler and restores the previous one.

If Firefox still opens the wrong application, reset `claude` under **Settings → General → Applications** to "Always ask" or the system default; Firefox remembers an explicitly chosen application separately from the system default.

## Prompt

`claude_ps1` renders the active profile as `(✳|personal)`. Toggle it like kube-ps1:

```zsh
claudeoff        # hide the segment in this shell
claudeon         # show it again
claudeoff -g     # hide it in new shells too
claudeon -g      # undo the global hide
```

The global setting is a marker file at `$CLAUDE_SWITCHER_HOME/.prompt-disabled`. `claudeon` and `claudeoff` without `-g` only affect the current shell, so one terminal can hide the segment while another shows it.

Customize with these variables, set before the prompt renders:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLAUDE_SWITCHER_PROMPT_SYMBOL` | `✳` | Leading glyph. Empty string removes it and its separator. |
| `CLAUDE_SWITCHER_PROMPT_SYMBOL_COLOR` | `208` | Symbol color, as a `%F{...}` name or 256-color number. |
| `CLAUDE_SWITCHER_PROMPT_PROFILE_COLOR` | `cyan` | Profile name color. |
| `CLAUDE_SWITCHER_PROMPT_PREFIX` | `(` | Opening text. |
| `CLAUDE_SWITCHER_PROMPT_SEPARATOR` | `\|` | Text between symbol and profile. |
| `CLAUDE_SWITCHER_PROMPT_SUFFIX` | `)` | Closing text. |
| `CLAUDE_SWITCHER_PROMPT_HIDE_IF_DEFAULT` | `false` | Set to `true` to show the segment only for named profiles. |
| `CLAUDE_SWITCHER_PROMPT_ENABLED` | `on` | Set to `off` **before sourcing the plugin** to start shells hidden. Afterwards, use `claudeoff`. |

`SYMBOL`, `PREFIX`, `SEPARATOR`, and `SUFFIX` are honored when set to an empty string, so `CLAUDE_SWITCHER_PROMPT_PREFIX=` drops the parenthesis rather than restoring the default. The color variables fall back to their defaults when empty.

## Proxies

Proxy aliases work unchanged:

```zsh
alias claude-proxy="HTTPS_PROXY=http://127.0.0.1:8118 HTTP_PROXY=http://127.0.0.1:8118 claude"
alias claude-desktop-proxy='claude-desktop --proxy-server="http://127.0.0.1:8118"'
```

zsh expands the alias body's command word after an assignment prefix, so `claude` still resolves to the plugin's function. The proxy variables are scoped to that single call and reach the Claude Code binary with the profile's `CLAUDE_CONFIG_DIR` applied. `claude-desktop-proxy` needs no prefix at all: `--proxy-server` is passed through to the Desktop binary after the profile's `--user-data-dir`.

Functions are an alternative for shells that never source the aliases, such as scripts. Use these instead of the aliases above, not alongside them, since a function cannot share a name with a defined alias:

```zsh
claude-proxy() {
  local -x HTTPS_PROXY=http://127.0.0.1:8118 HTTP_PROXY=http://127.0.0.1:8118
  claude "$@"
}

claude-desktop-proxy() {
  claude-desktop --proxy-server="http://127.0.0.1:8118" "$@"
}
```

Set the initial profile before sourcing the plugin:

```zsh
export CLAUDE_SWITCHER_DEFAULT_PROFILE=personal
```
