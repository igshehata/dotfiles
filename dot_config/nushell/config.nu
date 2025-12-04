# config.nu
#
# Installed by:
# version = "0.106.1"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# Nushell sets "sensible defaults" for most configuration settings, 
# so your `config.nu` only needs to override these defaults if desired.
#
# You can open this file in your default editor using:
#     config nu
#
# You can also pretty-print and page through the documentation for configuration
# options using:
#     config nu --doc | nu-highlight | less -R
$env.config.edit_mode = 'vi'

# Transient prompt configuration
$env.TRANSIENT_PROMPT_COMMAND = {|| starship module character }
$env.TRANSIENT_PROMPT_COMMAND_RIGHT = {|| starship module time }

# Initialize atuin (history sync)
source ~/.local/share/atuin/init.nu

# ============================================================================
# Git Aliases (from nu_scripts)
# ============================================================================
use ~/.config/nushell/git-aliases.nu *

# ============================================================================
# Aliases
# ============================================================================
alias ci = code-insiders
alias ag = agy
alias ?? = aichat
alias ls = eza -l --no-permissions --icons --git
alias ll = eza -la --no-permissions --icons --git
alias la = eza -a --icons --git
alias lt = eza -T --no-permissions --icons --level=2 --git
alias llt = eza -lT --no-permissions --icons --level=2 --git
alias py = python3
alias pip = pip3

# ============================================================================
# Television (tv) - Smart Autocomplete with Fuzzy Finding
# Ctrl+T: Fuzzy find files, directories, and commands
# Note: Ctrl+R remains with atuin for shell history
# ============================================================================

def tv_smart_autocomplete [] {
    let line = (commandline)
    let cursor = (commandline get-cursor)
    let lhs = ($line | str substring 0..$cursor)
    let rhs = ($line | str substring $cursor..)
    let output = (tv --inline --autocomplete-prompt $lhs | str trim)

    if ($output | str length) > 0 {
        let needs_space = not ($lhs | str ends-with " ")
        let lhs_with_space = if $needs_space { $"($lhs) " } else { $lhs }
        let new_line = $lhs_with_space + $output + $rhs
        let new_cursor = ($lhs_with_space + $output | str length)
        commandline edit --replace $new_line
        commandline set-cursor $new_cursor
    }
}

# Bind Ctrl+T for TV smart autocomplete
$env.config = (
  $env.config
  | upsert keybindings (
      $env.config.keybindings
      | append [
          {
              name: tv_completion,
              modifier: Control,
              keycode: char_t,
              mode: [vi_normal, vi_insert, emacs],
              event: {
                  send: executehostcommand,
                  cmd: "tv_smart_autocomplete"
              }
          }
      ]
  )
)
