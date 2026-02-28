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

# Claude Code (native installer)
$env.PATH = ($env.PATH | split row (char esep) | prepend ($env.HOME | path join '.local' 'bin'))

# Initialize fnm (Fast Node Manager)
if ((which fnm | length) > 0) {
  fnm env --json | from json | load-env
  $env.PATH = ($env.PATH | split row (char esep) | prepend $"($env.FNM_MULTISHELL_PATH)/bin")
}

# Keep generated init scripts in Nu vendor autoload so they are loaded automatically.
let nu_vendor_autoload = ($nu.data-dir | path join "vendor/autoload")
mkdir $nu_vendor_autoload

if ((which starship | length) > 0) {
  starship init nu | save -f ($nu_vendor_autoload | path join "starship.nu")
}

if ((which atuin | length) > 0) {
  atuin init nu | save -f ($nu_vendor_autoload | path join "atuin.nu")
}

if ((which carapace | length) > 0) {
  carapace _carapace nushell | save -f ($nu_vendor_autoload | path join "carapace.nu")
}

if ((which zoxide | length) > 0) {
  zoxide init nushell | save -f ($nu_vendor_autoload | path join "zoxide.nu")
}

# ============================================================================
# Rustup/Cargo - Add Rust toolchain to PATH
# ============================================================================
$env.PATH = ($env.PATH | split row (char esep) | prepend ($env.HOME | path join '.cargo' 'bin'))

# ============================================================================
# Bun - Add Bun runtime to PATH
# ============================================================================
$env.PATH = ($env.PATH | split row (char esep) | prepend ($env.HOME | path join '.bun' 'bin'))
