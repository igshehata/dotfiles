#!/usr/bin/env bash
# vps.sh — set up your user environment on an Ubuntu VPS from this dotfiles repo.
#
#   curl -fsSL https://raw.githubusercontent.com/igshehata/dotfiles/main/vps.sh | bash
#
# Run it as your normal sudo user (not root), over SSH, once the server is
# hardened and on Tailscale. It installs Homebrew and Nix, applies the dotfiles
# (which install the Brewfile tools and the mise languages), applies
# ~/nix-config/server.nix with system-manager, makes Homebrew's fish the login
# shell, then audits the hardening and prints PASS/FAIL per check.
# Safe to re-run: every step checks before acting; a re-run updates the dotfiles.
#
# Wrapped in a function so bash reads the whole script before running any of it
# (curl | bash safe). Interactive prompts read from /dev/tty.
vps_main() {

set -uo pipefail

DOTFILES_USER="igshehata"
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
BREW="$BREW_PREFIX/bin/brew"
FISH="$BREW_PREFIX/bin/fish"

info() { printf '\033[34m[INFO]\033[0m %s\n' "$1"; }
ok()   { printf '\033[32m[OK]\033[0m   %s\n' "$1"; }
warn() { printf '\033[33m[WARN]\033[0m %s\n' "$1"; }
fail() { printf '\033[31m[FAIL]\033[0m %s\n' "$1"; }

if [[ "$(uname -s)" != "Linux" ]] || ! command -v apt-get >/dev/null 2>&1; then
    fail "vps.sh supports Ubuntu/Debian only"
    return 1
fi
if [[ $EUID -eq 0 ]]; then
    fail "run as your normal sudo user, not root"
    return 1
fi

info "sudo is needed for packages, Homebrew's directory, Nix and the login shell"
sudo -v </dev/tty || { fail "sudo failed"; return 1; }

# --- 1. apt prerequisites -----------------------------------------------------
# build tools + curl/file/git/procps for Homebrew, libreadline-dev for mise's
# lua build, kitty-terminfo so tmux works from a kitty-protocol terminal.
local pkgs=(build-essential procps curl file git libreadline-dev kitty-terminfo)
local missing=()
local p
for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    info "Installing apt packages: ${missing[*]}"
    sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" </dev/null \
        || { fail "apt install failed"; return 1; }
fi
ok "apt prerequisites"

# --- 2. Homebrew --------------------------------------------------------------
if [[ ! -x "$BREW" ]]; then
    info "Installing Homebrew to $BREW_PREFIX"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null \
        || { fail "Homebrew install failed"; return 1; }
fi
eval "$("$BREW" shellenv)"
ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"

# --- 2b. Nix (Determinate installer; flakes on, uninstall: /nix/nix-installer uninstall)
NIX_PROFILE_SH="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
if [[ ! -e "$NIX_PROFILE_SH" ]]; then
    info "Installing Nix"
    curl --proto '=https' --tlsv1.2 -sSfL https://install.determinate.systems/nix \
        | sh -s -- install --no-confirm \
        || { fail "Nix install failed"; return 1; }
fi
set +u
# shellcheck disable=SC1090
. "$NIX_PROFILE_SH"
set -u
ok "$(nix --version)"

# --- 3. Dotfiles (installs mise, Brewfile tools, mise languages) --------------
command -v chezmoi >/dev/null 2>&1 || brew install chezmoi || { fail "chezmoi install failed"; return 1; }
if [[ -d "$HOME/.local/share/chezmoi/.git" ]]; then
    info "Updating dotfiles (chezmoi update)"
    chezmoi update </dev/tty || warn "chezmoi update reported errors — rerun: chezmoi update"
else
    info "Applying dotfiles from github.com/$DOTFILES_USER/dotfiles (20-30 min on a fresh server)"
    chezmoi init --apply "$DOTFILES_USER" </dev/tty || warn "chezmoi apply reported errors — rerun: chezmoi apply"
fi
ok "dotfiles"

# --- 3b. system-manager (~/nix-config systemConfigs.default, pinned by flake.lock)
if [[ -f "$HOME/nix-config/flake.nix" ]]; then
    info "Applying ~/nix-config with system-manager"
    if nix run --inputs-from "$HOME/nix-config" system-manager -- switch --flake "$HOME/nix-config" --sudo </dev/tty; then
        ok "system-manager"
    else
        warn "system-manager switch failed — rerun: sms"
    fi
else
    warn "$HOME/nix-config missing — dotfiles not applied, skipping system-manager"
fi

# --- 4. Login shell -----------------------------------------------------------
if [[ -x "$FISH" ]]; then
    grep -qx "$FISH" /etc/shells || echo "$FISH" | sudo tee -a /etc/shells >/dev/null
    if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$FISH" ]]; then
        sudo chsh -s "$FISH" "$USER" && ok "login shell → $FISH (takes effect on next login)"
    else
        ok "login shell is $FISH"
    fi
    if dpkg -s fish >/dev/null 2>&1; then
        info "Removing Ubuntu's older fish package (Homebrew's fish replaces it)"
        sudo apt-get remove -y -qq fish </dev/null || warn "could not remove apt fish"
    fi
else
    warn "Homebrew fish missing — login shell unchanged (check: brew bundle check --global)"
fi

# --- 5. Audit (read-only) -----------------------------------------------------
echo
info "Hardening audit"
local passed=0 failed=0
check() {
    if eval "$2" >/dev/null 2>&1; then ok "$1"; passed=$((passed + 1))
    else fail "$1"; failed=$((failed + 1)); fi
}
# Read inside check's eval strings below.
# shellcheck disable=SC2034
local sshd_cfg ufw_status
# shellcheck disable=SC2034
sshd_cfg="$(sudo sshd -T 2>/dev/null)"
# shellcheck disable=SC2034
ufw_status="$(sudo ufw status 2>/dev/null)"
check "root SSH login disabled"              'grep -qx "permitrootlogin no" <<<"$sshd_cfg"'
check "SSH password login disabled"          'grep -qx "passwordauthentication no" <<<"$sshd_cfg" && grep -qx "kbdinteractiveauthentication no" <<<"$sshd_cfg"'
check "no default 'ubuntu' account"          '! getent passwd ubuntu'
check "firewall active"                      'grep -q "^Status: active" <<<"$ufw_status"'
check "SSH not open to the internet"         '! grep -qE "^(22|22/tcp|OpenSSH)[[:space:]]" <<<"$ufw_status"'
check "Tailscale traffic allowed"            'grep -q "on tailscale0" <<<"$ufw_status"'
check "Tailscale connected"                  'tailscale status'
check "Tailscale SSH off (use OpenSSH)"      'tailscale debug prefs | grep -q "\"RunSSH\": false"'
check "exit-node forwarding enabled"         '[[ "$(sysctl -n net.ipv4.ip_forward)" == 1 ]]'
check "automatic security updates enabled"   'systemctl is-enabled unattended-upgrades'
check "Brewfile fully installed"             'brew bundle check --global --no-upgrade'
check "mise languages installed"             '[[ -z "$("$HOME/.local/bin/mise" ls --missing 2>/dev/null)" ]]'
check "Nix daemon running"                   'systemctl is-active nix-daemon'
check "system-manager config active"         'systemctl is-active system-manager.target'

echo
if [[ $failed -eq 0 ]]; then
    ok "$passed/$passed checks passed — log out and back in to start fish"
else
    warn "$failed of $((passed + failed)) checks failed — see [FAIL] lines above"
fi
}

vps_main "$@"
