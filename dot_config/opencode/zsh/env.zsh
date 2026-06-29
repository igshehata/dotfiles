#!/usr/bin/env zsh
# OpenCode / non-interactive zsh environment
#
# Goal: mirror the important non-interactive parts of ~/.config/fish/config.fish
# so tool execution under zsh has the same PATH/exports and avoids "command not found".
#
# IMPORTANT: keep this file safe for non-interactive shells.
# Do not depend on TTY, prompt theming, keybindings, or interactive-only hooks.

# Avoid double-loading when sourced from both ~/.zshenv and ~/.zshrc.
if [[ -n "${__OPENCODE_ZSH_ENV_LOADED:-}" ]]; then
  return 0
fi
export __OPENCODE_ZSH_ENV_LOADED=1

# Avoid strict modes here: this file is sourced by non-interactive shells
# (including tool runners) and some third-party init snippets assume unset vars.
set -o pipefail

# Homebrew environment (equivalent to: /opt/homebrew/bin/brew shellenv | source)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Nix darwin system binaries
if [[ -d /run/current-system/sw/bin ]]; then
  export PATH="/run/current-system/sw/bin:${PATH}"
fi

# Claude Code (native installer)
if [[ -d "${HOME}/.local/bin" ]]; then
  export PATH="${HOME}/.local/bin:${PATH}"
fi

# bun (fish: set -gx BUN_INSTALL "$HOME/.bun"; fish_add_path "$BUN_INSTALL/bin")
export BUN_INSTALL="${HOME}/.bun"
if [[ -d "${BUN_INSTALL}/bin" ]]; then
  export PATH="${BUN_INSTALL}/bin:${PATH}"
fi

# uv / python env helpers (fish: source ~/.local/bin/env.fish)
# zsh equivalent created by installer is typically ~/.local/bin/env
if [[ -f "${HOME}/.local/bin/env" ]]; then
  # shellcheck disable=SC1090
  . "${HOME}/.local/bin/env"
fi

# atuin env (fish: source ~/.atuin/bin/env.fish)
if [[ -f "${HOME}/.atuin/bin/env" ]]; then
  # shellcheck disable=SC1090
  . "${HOME}/.atuin/bin/env"
fi

# rustup env (fish: source ~/.cargo/env.fish)
if [[ -f "${HOME}/.cargo/env" ]]; then
  # shellcheck disable=SC1090
  . "${HOME}/.cargo/env"
fi

# fnm (fish interactive uses: fnm env --use-on-cd | source)
# For non-interactive shells, a plain `fnm env` is sufficient.
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env)"
fi

# mise (used in your zshrc). For non-interactive shells we mainly need PATH.
# `mise activate zsh` also installs hooks and expects zsh hook arrays to exist.
if command -v mise >/dev/null 2>&1; then
  typeset -ga precmd_functions preexec_functions chpwd_functions 2>/dev/null || true
  eval "$(mise activate zsh)"
fi

# zoxide/carapace/starship/tv are interactive-only in fish; skip here.
