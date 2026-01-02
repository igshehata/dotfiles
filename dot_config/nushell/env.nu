# env.nu
#
# Installed by:
# version = "0.106.1"
#
# Previously, environment variables were typically configured in `env.nu`.
# In general, most configuration can and should be performed in `config.nu`
# or one of the autoload directories.
#
# This file is generated for backwards compatibility for now.
# It is loaded before config.nu and login.nu
#
# See https://www.nushell.sh/book/configuration.html
#
# Also see `help config env` for more options.
#
# You can remove these comments if you want or leave
# them for future reference.
$env.EDITOR = 'nvim'

# Nix darwin system binaries
$env.PATH = ($env.PATH | split row (char esep) | prepend '/run/current-system/sw/bin')

# Initialize fnm (Fast Node Manager)
fnm env --json | from json | load-env
$env.PATH = ($env.PATH | split row (char esep) | prepend $"($env.FNM_MULTISHELL_PATH)/bin")

mkdir ($nu.data-dir | path join "vendor/autoload")
starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")
source ~/.zoxide.nu
source ~/.cache/carapace/init.nu
# ============================================================================
# Rustup/Cargo - Add Rust toolchain to PATH
# ============================================================================
$env.PATH = ($env.PATH | split row (char esep) | prepend ($env.HOME | path join '.cargo' 'bin'))

# ============================================================================
# Bun - Add Bun runtime to PATH
# ============================================================================
$env.PATH = ($env.PATH | split row (char esep) | prepend ($env.HOME | path join '.bun' 'bin'))
zoxide init nushell | save -f ~/.zoxide.nu
