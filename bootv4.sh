#!/usr/bin/env bash
# bootv4 — macOS bootstrap (curl|bash safe)
# Wrap everything in a function so bash parses the entire pipe before executing.
bootv4_main() {

set -uo pipefail
# NO set -e — we check return codes explicitly

# ============================================================================
# Configuration
# ============================================================================
CHEZMOI_SOURCE="$HOME/.local/share/chezmoi"
NIX_CONFIG="$HOME/nix-config"
DOTFILES_REPO="https://github.com/igshehata/dotfiles.git"
CURRENT_USER="$(whoami)"
HOSTNAME="$(hostname -s)"
START_PHASE=0
FINAL_PHASE=10

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --from-phase)
            START_PHASE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: bootv4.sh [--from-phase N]"
            return 1
            ;;
    esac
done

if ! [[ "$START_PHASE" =~ ^[0-9]+$ ]]; then
    printf "[FAIL] --from-phase must be a number\n"
    return 1
fi

if [[ "$START_PHASE" -lt 0 || "$START_PHASE" -gt "$FINAL_PHASE" ]]; then
    printf "[FAIL] --from-phase must be between 0 and %s\n" "$FINAL_PHASE"
    return 1
fi

# ============================================================================
# Helper Functions
# ============================================================================
info()    { printf "\033[34m[INFO]\033[0m %s\n" "$1"; }
success() { printf "\033[32m[OK]\033[0m   %s\n" "$1"; }
warn()    { printf "\033[33m[WARN]\033[0m %s\n" "$1"; }
fail()    { printf "\033[31m[FAIL]\033[0m %s\n" "$1"; }
skip()    { printf "\033[90m[SKIP]\033[0m %s\n" "$1"; }

tty_read() { read "$@" </dev/tty; }

confirm() {
    local msg="${1:-Continue?}"
    local response
    printf "%s [y/N] " "$msg" >/dev/tty
    read -r response </dev/tty
    [[ "$response" =~ ^[Yy] ]]
}

# Result tracking for Phase 10 verification
RESULTS=()
track() { RESULTS+=("$1|$2|$3"); }  # category|name|pass/fail

should_run() {
    local phase_num="$1"
    [[ "$phase_num" -ge "$START_PHASE" ]]
}

run_phase() {
    local phase_num="$1"
    local phase_fn="$2"

    if should_run "$phase_num"; then
        "$phase_fn"
    fi
}

cleanup_legacy_state() {
    local legacy_state_file="$HOME/.bootv4-state"
    if [[ -f "$legacy_state_file" ]]; then
        rm -f "$legacy_state_file"
        info "Removed legacy state tracker: $legacy_state_file"
    fi
}

# ============================================================================
# Phase 0: Prerequisites (Xcode CLT)
# ============================================================================
phase_0() {
    info "Phase 0: Xcode Command Line Tools"

    if xcode-select -p &>/dev/null; then
        skip "Xcode CLT already installed"
        return 0
    fi

    info "Installing Xcode Command Line Tools..."
    xcode-select --install 2>/dev/null

    # Wait for installation to complete
    info "Waiting for Xcode CLT installation (this opens a system dialog)..."
    until xcode-select -p &>/dev/null; do
        sleep 5
    done

    success "Xcode CLT installed"
}

# ============================================================================
# Phase 1: Nix (Determinate installer)
# ============================================================================
phase_1() {
    info "Phase 1: Nix"

    if command -v nix &>/dev/null; then
        skip "Nix already installed ($(nix --version))"
        return 0
    fi

    info "Installing Nix via Determinate installer..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install </dev/tty

    # Source nix for this session
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        # shellcheck disable=SC1091
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi

    if command -v nix &>/dev/null; then
        success "Nix installed ($(nix --version))"
    else
        fail "Nix installation failed — 'nix' not found in PATH"
        return 1
    fi
}

# ============================================================================
# Phase 2: Clone dotfiles (chezmoi source)
# ============================================================================
phase_2() {
    info "Phase 2: Clone dotfiles"

    if [[ -d "$CHEZMOI_SOURCE/.git" ]]; then
        skip "Dotfiles already cloned at $CHEZMOI_SOURCE"
        # Pull latest changes
        info "Pulling latest changes..."
        git -C "$CHEZMOI_SOURCE" pull --ff-only 2>/dev/null || warn "Could not pull (offline or conflict)"
        return 0
    fi

    # chezmoi may not be installed yet on a fresh machine
    if command -v chezmoi &>/dev/null; then
        info "Cloning via chezmoi init..."
        chezmoi init --source "$CHEZMOI_SOURCE" "$DOTFILES_REPO"
    else
        info "chezmoi not yet available — cloning via git..."
        git clone "$DOTFILES_REPO" "$CHEZMOI_SOURCE"
    fi

    if [[ -d "$CHEZMOI_SOURCE/.git" ]]; then
        success "Dotfiles cloned to $CHEZMOI_SOURCE"
    else
        fail "Failed to clone dotfiles"
        return 1
    fi
}

# ============================================================================
# Phase 3: Configure nix-config (sed username/hostname)
# ============================================================================
phase_3() {
    info "Phase 3: Configure nix-config for $CURRENT_USER@$HOSTNAME"

    if [[ ! -d "$CHEZMOI_SOURCE/nix-config" ]]; then
        fail "Missing nix-config in $CHEZMOI_SOURCE"
        return 1
    fi

    info "Syncing nix-config from chezmoi source..."
    mkdir -p "$NIX_CONFIG"
    cp "$CHEZMOI_SOURCE/nix-config/configuration.nix" "$NIX_CONFIG/configuration.nix"
    cp "$CHEZMOI_SOURCE/nix-config/flake.nix" "$NIX_CONFIG/flake.nix"

    local config_nix="$NIX_CONFIG/configuration.nix"
    local flake_nix="$NIX_CONFIG/flake.nix"

    # 1. homebrew.user in configuration.nix
    if grep -q "user = \"$CURRENT_USER\"" "$config_nix"; then
        skip "homebrew.user already set to $CURRENT_USER"
    else
        sed -E -i '' "s|(^[[:space:]]*user[[:space:]]*=[[:space:]]*\")[^\"]*(\".*$)|\\1$CURRENT_USER\\2|" "$config_nix"
        if grep -q "user = \"$CURRENT_USER\"" "$config_nix"; then
            success "homebrew.user set to $CURRENT_USER"
        else
            fail "Failed to set homebrew.user"
            return 1
        fi
    fi

    # 2. users.users."..." in configuration.nix
    if grep -q "users.users.\"$CURRENT_USER\"" "$config_nix"; then
        skip "users.users already set to $CURRENT_USER"
    else
        sed -E -i '' "s|(users\.users\.\")[^\"]*(\")|\\1$CURRENT_USER\\2|" "$config_nix"
        if grep -q "users.users.\"$CURRENT_USER\"" "$config_nix"; then
            success "users.users set to $CURRENT_USER"
        else
            fail "Failed to set users.users"
            return 1
        fi
    fi

    # 3. system.primaryUser in configuration.nix
    if grep -q "system.primaryUser = \"$CURRENT_USER\"" "$config_nix"; then
        skip "system.primaryUser already set to $CURRENT_USER"
    else
        sed -E -i '' "s|(^[[:space:]]*system\.primaryUser[[:space:]]*=[[:space:]]*\")[^\"]*(\".*$)|\\1$CURRENT_USER\\2|" "$config_nix"
        if grep -q "system.primaryUser = \"$CURRENT_USER\"" "$config_nix"; then
            success "system.primaryUser set to $CURRENT_USER"
        else
            fail "Failed to set system.primaryUser"
            return 1
        fi
    fi

    # 4. darwinConfigurations."..." in flake.nix
    if grep -q "darwinConfigurations.\"$HOSTNAME\"" "$flake_nix"; then
        skip "darwinConfigurations already set to $HOSTNAME"
    else
        sed -E -i '' "s|(darwinConfigurations\.\")[^\"]*(\")|\\1$HOSTNAME\\2|" "$flake_nix"
        if grep -q "darwinConfigurations.\"$HOSTNAME\"" "$flake_nix"; then
            success "darwinConfigurations set to $HOSTNAME"
        else
            fail "Failed to set darwinConfigurations host"
            return 1
        fi
    fi

}

# ============================================================================
# Phase 4: Homebrew update + darwin-rebuild switch
# ============================================================================
phase_4() {
    info "Phase 4: Homebrew + darwin-rebuild"

    # Ensure homebrew is available
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true

    if ! command -v brew &>/dev/null; then
        warn "Homebrew not found — Nix/darwin-rebuild will install it"
    else
        info "Updating Homebrew..."
        brew update || warn "brew update failed — continuing"
        info "Upgrading existing formulae (skipping casks to avoid stale app-link failures)..."
        brew upgrade --formula || warn "brew formula upgrade failed — continuing"
    fi

    local rebuild_host="$HOSTNAME"
    if ! grep -q "darwinConfigurations.\"$rebuild_host\"" "$NIX_CONFIG/flake.nix"; then
        local detected_host
        detected_host=$(sed -nE 's/^[[:space:]]*darwinConfigurations\."([^"]+)".*/\1/p' "$NIX_CONFIG/flake.nix" | head -1)
        if [[ -n "$detected_host" ]]; then
            warn "Flake host '$rebuild_host' not found; using '$detected_host' from flake.nix"
            rebuild_host="$detected_host"
        else
            fail "No darwinConfigurations entry found in $NIX_CONFIG/flake.nix"
            return 1
        fi
    fi

    info "Running darwin-rebuild switch --flake ~/nix-config#$rebuild_host ..."
    sudo darwin-rebuild switch --flake "$NIX_CONFIG#$rebuild_host" </dev/tty
    local rebuild_rc=$?

    if [[ $rebuild_rc -ne 0 ]]; then
        fail "darwin-rebuild failed (exit $rebuild_rc)"
        return 1
    fi

    # Refresh PATH for this session
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    export PATH="/run/current-system/sw/bin:$PATH"
    hash -r

    success "darwin-rebuild completed"

    local has_brew=0
    if command -v brew &>/dev/null; then
        has_brew=1
    fi

    # Verify formulas by brew install state OR command availability in PATH
    # (some tools are intentionally installed via Nix and won't appear in brew list)
    info "Verifying CLI tools are available..."
    local formula_checks=(
        "mise:mise" "direnv:direnv" "aichat:aichat" "atuin:atuin" "bash:bash"
        "biome:biome" "carapace:carapace" "chezmoi:chezmoi" "commitizen:cz"
        "difftastic:difft" "eza:eza" "fd:fd" "ffmpeg:ffmpeg" "fish:fish"
        "fnm:fnm" "fzf:fzf" "gemini-cli:gemini-cli" "gh:gh" "gnupg:gpg"
        "go:go" "jq:jq" "k6:k6" "kind:kind" "lua:lua" "luajit:luajit"
        "node:node" "nushell:nu" "openjdk:java" "pinentry:pinentry"
        "pnpm:pnpm" "starship:starship" "tmux:tmux" "tree:tree"
        "zoxide:zoxide" "opencode:opencode" "zig:zig" "neofetch:neofetch"
        "pandoc:pandoc" "trivy:trivy" "yazi:yazi" "ripgrep:rg" "bat:bat"
        "neovim:nvim" "television:tv" "rustup:rustup" "bun:bun"
        "python@3.13:python3.13"
    )

    for check in "${formula_checks[@]}"; do
        local formula="${check%%:*}"
        local cmd="${check##*:}"

        if { [[ $has_brew -eq 1 ]] && brew list --formula "$formula" &>/dev/null; } || command -v "$cmd" &>/dev/null; then
            track "Brews" "$formula" "pass"
        else
            track "Brews" "$formula" "fail"
            warn "Tool not found: $formula (expected command: $cmd)"
        fi
    done

    local casks=(
        superwhisper 1password 1password-cli antigravity apidog arc
        discord ghostty google-chrome obsidian postman raycast
        visual-studio-code@insiders wezterm font-jetbrains-mono-nerd-font
    )

    for cask in "${casks[@]}"; do
        if [[ $has_brew -eq 1 ]] && brew list --cask "$cask" &>/dev/null; then
            track "Casks" "$cask" "pass"
        else
            track "Casks" "$cask" "fail"
            warn "Cask not found: $cask"
        fi
    done

    # Ghostty cask can be installed while app bundle is missing from /Applications.
    if [[ $has_brew -eq 1 ]] && brew list --cask ghostty &>/dev/null && [[ ! -d "/Applications/Ghostty.app" ]]; then
        warn "Ghostty cask is installed but /Applications/Ghostty.app is missing — reinstalling cask"
        brew reinstall --cask ghostty || warn "Ghostty reinstall failed"
    fi

    if [[ -d "/Applications/Ghostty.app" ]]; then
        track "Casks" "ghostty app bundle" "pass"
    else
        track "Casks" "ghostty app bundle" "fail"
        warn "Ghostty.app is still missing in /Applications"
    fi

}

# ============================================================================
# Phase 5: 1Password CLI setup
# ============================================================================
phase_5() {
    info "Phase 5: 1Password CLI"

    if ! command -v op &>/dev/null; then
        fail "1Password CLI (op) is not installed"
        return 1
    fi

    if op whoami &>/dev/null; then
        skip "1Password CLI already signed in"
        return 0
    fi

    info "Signing into 1Password CLI..."
    eval "$(op signin --account my.1password.com)" </dev/tty

    info "Enabling biometric unlock..."
    op settings set biometric true 2>/dev/null || warn "Could not enable biometric (may need GUI app open)"

    if op whoami &>/dev/null; then
        success "1Password CLI signed in"
    else
        warn "1Password CLI sign-in may have failed — continuing anyway"
    fi

}

# ============================================================================
# Phase 6: chezmoi init --apply
# ============================================================================
phase_6() {
    info "Phase 6: chezmoi apply"

    if ! command -v chezmoi &>/dev/null; then
        fail "chezmoi not found in PATH — was it installed in Phase 4?"
        return 1
    fi

    # Check if chezmoi data already exists (re-run scenario)
    if [[ -f "$HOME/.config/chezmoi/chezmoi.toml" ]]; then
        info "chezmoi data exists — running chezmoi apply --force..."
        chezmoi apply --force </dev/tty
    else
        info "First run — chezmoi init will prompt for template values..."
        chezmoi init --apply </dev/tty
    fi
    local chezmoi_rc=$?

    if [[ $chezmoi_rc -ne 0 ]]; then
        fail "chezmoi apply failed (exit $chezmoi_rc)"
        return 1
    fi

    # Validate 1Password template hydration for Atuin key material.
    if chezmoi execute-template '{{ onepasswordRead "op://Dev/AtuinSyncKey/notesPlain" }}' &>/dev/null; then
        success "chezmoi can hydrate 1Password secrets"
    else
        warn "1Password secret hydration failed — Atuin sync will fail until this works"
    fi

    # Nushell on macOS loads from $nu.default-config-dir (usually App Support).
    # Keep ~/.config/nushell as source-of-truth and link active files to it.
    if command -v nu &>/dev/null; then
        local nu_default_dir
        nu_default_dir="$(nu -c 'print $nu.default-config-dir' 2>/dev/null || true)"
        if [[ -n "$nu_default_dir" ]]; then
            mkdir -p "$nu_default_dir"
            for nu_file in config.nu env.nu; do
                local src="$HOME/.config/nushell/$nu_file"
                local dst="$nu_default_dir/$nu_file"
                if [[ "$src" == "$dst" ]]; then
                    continue
                fi
                if [[ -f "$src" ]]; then
                    ln -sfn "$src" "$dst"
                fi
            done
            success "Nushell active config now points to ~/.config/nushell"
        else
            warn "Could not determine Nushell default config directory"
        fi

        # Regenerate shell integration init files for Nu autoload path.
        local nu_data_dir
        nu_data_dir="$(nu -c 'print $nu.data-dir' 2>/dev/null || true)"
        if [[ -n "$nu_data_dir" ]]; then
            local nu_vendor_dir="$nu_data_dir/vendor/autoload"
            mkdir -p "$nu_vendor_dir"

            command -v starship &>/dev/null && starship init nu > "$nu_vendor_dir/starship.nu"
            command -v atuin &>/dev/null && atuin init nu > "$nu_vendor_dir/atuin.nu"
            command -v carapace &>/dev/null && carapace _carapace nushell > "$nu_vendor_dir/carapace.nu"
            command -v zoxide &>/dev/null && zoxide init nushell > "$nu_vendor_dir/zoxide.nu"

            success "Regenerated Nushell vendor autoload scripts"
        fi
    fi

    # Ghostty reads XDG config first, then macOS path; remove legacy file so XDG wins.
    local ghostty_legacy="$HOME/Library/Application Support/com.mitchellh.ghostty/config"
    if [[ -f "$ghostty_legacy" ]]; then
        local ghostty_backup
        ghostty_backup="${ghostty_legacy}.bootv4.bak.$(date +%Y%m%d%H%M%S)"
        mv "$ghostty_legacy" "$ghostty_backup"
        success "Moved legacy Ghostty config to $ghostty_backup"
    fi

    # Ensure XDG Ghostty path is materialized even on fresh machines.
    mkdir -p "$HOME/.config/ghostty"
    chezmoi apply --force "$HOME/.config/ghostty/config" </dev/tty 2>/dev/null || warn "Could not refresh Ghostty XDG config"

    # Verify key deployed files
    local configs=(
        "$HOME/.config/fish/config.fish"
        "$HOME/.config/tmux/tmux.conf"
        "$HOME/.config/atuin/config.toml"
        "$HOME/.config/nushell/config.nu"
        "$HOME/.config/nushell/env.nu"
        "$HOME/.config/ghostty/config"
        "$HOME/.config/starship.toml"
        "$HOME/.gitconfig"
    )

    for cfg in "${configs[@]}"; do
        if [[ -f "$cfg" ]]; then
            track "Configs" "$cfg" "pass"
        else
            track "Configs" "$cfg" "fail"
            warn "Config not deployed: $cfg"
        fi
    done

    # Extra check: atuin config has a real sync key (not a template placeholder)
    if [[ -f "$HOME/.config/atuin/config.toml" ]]; then
        local key_line
        key_line=$(grep '^sync_key' "$HOME/.config/atuin/config.toml" 2>/dev/null || true)
        if [[ -n "$key_line" && ! "$key_line" =~ \{\{ ]]; then
            track "Configs" "atuin sync_key" "pass"
        else
            track "Configs" "atuin sync_key" "fail"
            warn "Atuin config missing sync key or has template placeholder"
        fi
    fi

    success "chezmoi apply completed"
}

# ============================================================================
# Phase 7: SSH Key Setup + chezmoi remote switch
# ============================================================================
phase_7() {
    info "Phase 7: SSH Key Setup"

    # Test if SSH to GitHub already works
    local ssh_test
    ssh_test="$(ssh -T git@github.com 2>&1 || true)"
    if [[ "$ssh_test" == *"successfully authenticated"* ]]; then
        success "SSH to GitHub already works"
        track "SSH" "github" "pass"
    else
        info "SSH to GitHub is not configured yet."
        echo ""
        echo "  1) Use 1Password SSH Agent (recommended if you use 1P for SSH keys)"
        echo "  2) Generate a new local SSH key"
        echo "  3) Skip SSH setup for now"
        echo ""
        local ssh_choice
        printf "Choice [1/2/3]: " >/dev/tty
        tty_read -r ssh_choice

        case "$ssh_choice" in
            1)
                info "Setting up 1Password SSH Agent..."
                mkdir -p "$HOME/.ssh"

                local ssh_config="$HOME/.ssh/config"
                if [[ ! -f "$ssh_config" ]] || ! grep -q "IdentityAgent" "$ssh_config" 2>/dev/null; then
                    cat >> "$ssh_config" <<'SSHEOF'

# 1Password SSH Agent
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
SSHEOF
                    chmod 600 "$ssh_config"
                    success "SSH config updated with 1Password IdentityAgent"
                else
                    success "SSH config already has IdentityAgent"
                fi

                info "Make sure 'Use the SSH Agent' is enabled in 1Password > Settings > Developer"
                confirm "Press y after verifying 1Password SSH Agent is enabled"

                ssh_test="$(ssh -T git@github.com 2>&1 || true)"
                if [[ "$ssh_test" == *"successfully authenticated"* ]]; then
                    success "SSH via 1Password Agent works!"
                    track "SSH" "github" "pass"
                else
                    warn "SSH test failed. You may need to add your GitHub SSH key in 1Password."
                    track "SSH" "github" "fail"
                fi
                ;;
            2)
                info "Generating ed25519 SSH key..."
                local ssh_email
                printf "Email for SSH key: " >/dev/tty
                tty_read -r ssh_email
                ssh-keygen -t ed25519 -C "$ssh_email" -f "$HOME/.ssh/id_ed25519" </dev/tty
                eval "$(ssh-agent -s)"
                ssh-add "$HOME/.ssh/id_ed25519"

                echo ""
                info "Add this public key to GitHub (https://github.com/settings/keys):"
                echo ""
                cat "$HOME/.ssh/id_ed25519.pub"
                echo ""

                confirm "Press y after adding the key to GitHub"
                ssh_test="$(ssh -T git@github.com 2>&1 || true)"
                if [[ "$ssh_test" == *"successfully authenticated"* ]]; then
                    success "SSH key works!"
                    track "SSH" "github" "pass"
                else
                    warn "SSH test failed. Continuing — you can fix this later."
                    track "SSH" "github" "fail"
                fi
                ;;
            *)
                info "Skipping SSH setup. You can configure it later."
                return 0
                ;;
        esac
    fi

    # Switch chezmoi remote from HTTPS to SSH
    local current_remote
    current_remote="$(git -C "$CHEZMOI_SOURCE" remote get-url origin 2>/dev/null || true)"
    local ssh_remote="git@github.com:${DOTFILES_REPO#https://github.com/}"
    # Normalize: strip .git if present in both
    ssh_remote="${ssh_remote%.git}.git"

    if [[ "$current_remote" == git@* ]]; then
        success "chezmoi remote already uses SSH"
    elif [[ "$ssh_test" == *"successfully authenticated"* ]]; then
        info "Switching chezmoi remote from HTTPS to SSH..."
        git -C "$CHEZMOI_SOURCE" remote set-url origin "$ssh_remote"
        success "chezmoi remote switched to $ssh_remote"
    else
        info "SSH not working yet — keeping HTTPS remote. Switch later with:"
        info "  git -C $CHEZMOI_SOURCE remote set-url origin $ssh_remote"
    fi

}

# ============================================================================
# Phase 8: Shell plugins (Fisher, TPM)
# ============================================================================
phase_8() {
    info "Phase 8: Shell plugins"

    # --- Fisher ---
    if [[ -f "$HOME/.config/fish/functions/fisher.fish" ]]; then
        skip "Fisher already installed (deployed by chezmoi)"
    else
        info "Installing Fisher..."
        fish --no-config -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher" </dev/tty
        if [[ -f "$HOME/.config/fish/functions/fisher.fish" ]]; then
            success "Fisher installed"
        else
            warn "Fisher installation may have failed"
        fi
    fi

    # --- TPM (Tmux Plugin Manager) ---
    local tpm_dir="$HOME/.config/tmux/plugins/tpm"
    if [[ -d "$tpm_dir" ]]; then
        skip "TPM already installed"
    else
        info "Installing TPM..."
        git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
        if [[ -d "$tpm_dir" ]]; then
            success "TPM cloned"
        else
            warn "TPM clone failed"
        fi
    fi

    # Install tmux plugins via TPM
    if [[ -x "$tpm_dir/bin/install_plugins" ]]; then
        info "Installing tmux plugins via TPM..."
        "$tpm_dir/bin/install_plugins"
        success "Tmux plugins installed"
    fi

}

# ============================================================================
# Phase 9: Atuin hard reset + sync
# ============================================================================
phase_9() {
    info "Phase 9: Atuin hard reset + sync"

    if ! command -v atuin &>/dev/null; then
        fail "atuin not found in PATH"
        return 1
    fi

    # Hard reset requested: clear local Atuin data and auth/session state.
    info "Performing hard reset of local Atuin state..."
    atuin account logout >/dev/null 2>&1 || true
    rm -rf "$HOME/.local/share/atuin"
    rm -rf "$HOME/.config/atuin"
    mkdir -p "$HOME/.config/atuin"

    # Rehydrate atuin config from chezmoi (sync_key comes from 1Password template).
    # Use --force to avoid interactive "changed since chezmoi last wrote it" prompts.
    if ! chezmoi apply --force "$HOME/.config/atuin/config.toml"; then
        fail "Failed to apply atuin config with chezmoi"
        return 1
    fi

    if ! chezmoi execute-template '{{ onepasswordRead "op://Dev/AtuinSyncKey/notesPlain" }}' &>/dev/null; then
        fail "1Password secret hydration failed for Atuin sync key"
        return 1
    fi

    # Extract sync key from chezmoi-deployed config
    local atuin_config="$HOME/.config/atuin/config.toml"
    local atuin_key=""

    if [[ -f "$atuin_config" ]]; then
        atuin_key=$(python3 - <<'PY'
from pathlib import Path
import re
p = Path.home() / '.config' / 'atuin' / 'config.toml'
text = p.read_text() if p.exists() else ''
m = re.search(r'^\s*sync_key\s*=\s*(["\'])(.*)\1\s*$', text, re.M)
print(m.group(2) if m else '')
PY
)
    fi

    if [[ -z "$atuin_key" || "$atuin_key" == *"{{"* || "$atuin_key" == *"onepassword"* ]]; then
        fail "No valid atuin sync key after hard reset + chezmoi apply"
        return 1
    fi

    info "Atuin sync key found in config"

    local atuin_user
    printf "Atuin username: " >/dev/tty
    tty_read -r atuin_user

    info "Logging into atuin (will prompt for password)..."
    atuin account login -u "$atuin_user" -k "$atuin_key" </dev/tty
    local login_rc=$?

    if [[ $login_rc -ne 0 ]]; then
        fail "Atuin login failed (exit $login_rc)"
        return 1
    fi

    info "Running force sync..."
    local sync_output
    sync_output="$(atuin sync -f 2>&1)"
    local sync_rc=$?

    if [[ $sync_rc -eq 0 ]]; then
        success "Atuin synced"
        track "Shell" "atuin sync" "pass"
        return 0
    fi

    if [[ "$sync_output" == *"attempting to decrypt with incorrect key"* ]]; then
        warn "Atuin detected remote records encrypted with a different key"

        local backup_dir="$HOME/atuin-backups"
        local backup_ts
        backup_ts="$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        atuin history list > "$backup_dir/atuin-history-$backup_ts.txt" 2>/dev/null || true
        tar -czf "$backup_dir/atuin-state-$backup_ts.tgz" -C "$HOME" .local/share/atuin .config/atuin/config.toml 2>/dev/null || true
        info "Created Atuin safety backup in $backup_dir"

        if confirm "Overwrite remote Atuin store with current local history to repair mixed keys?"; then
            info "Rebuilding remote Atuin store from local data..."
            if ! atuin store push --force </dev/tty; then
                fail "Failed to push repaired Atuin store to remote"
                track "Shell" "atuin sync" "fail"
                return 1
            fi

            atuin sync -f >/dev/null 2>&1
            local repair_rc=$?
            if [[ $repair_rc -eq 0 ]]; then
                success "Atuin synced after remote store repair"
                track "Shell" "atuin sync" "pass"
                return 0
            fi

            fail "Atuin sync still failing after remote repair"
            track "Shell" "atuin sync" "fail"
            return 1
        fi

        fail "Mixed-key Atuin records remain (repair was skipped)"
        track "Shell" "atuin sync" "fail"
        return 1
    fi

    fail "Atuin sync failed"
    track "Shell" "atuin sync" "fail"
    return 1

}

# ============================================================================
# Phase 10: Verification + Summary
# ============================================================================
phase_10() {
    info "Phase 10: Final Verification"
    echo ""
    echo "========================================"
    echo "         VERIFICATION SUMMARY"
    echo "========================================"

    # Additional runtime checks (beyond what phases already tracked)

    # Shell integrations
    local shell_checks=(
        "starship:starship"
        "atuin:atuin"
        "zoxide:zoxide"
        "carapace:carapace"
        "chezmoi:chezmoi"
        "fish:fish"
        "nu:nu"
        "nvim:nvim"
        "tmux:tmux"
        "tv:tv"
        "rustup:rustup"
        "git:git"
    )

    for check in "${shell_checks[@]}"; do
        local label="${check%%:*}"
        local cmd="${check##*:}"
        if command -v "$cmd" &>/dev/null; then
            track "Tools" "$label" "pass"
        else
            track "Tools" "$label" "fail"
        fi
    done

    # Config files
    local config_checks=(
        "$HOME/.config/fish/config.fish"
        "$HOME/.config/tmux/tmux.conf"
        "$HOME/.config/atuin/config.toml"
        "$HOME/.config/starship.toml"
        "$HOME/.config/nushell/config.nu"
        "$HOME/.config/nushell/env.nu"
        "$HOME/Library/Application Support/nushell/config.nu"
        "$HOME/Library/Application Support/nushell/env.nu"
        "$HOME/.config/ghostty/config"
        "$HOME/.gitconfig"
    )

    for cfg in "${config_checks[@]}"; do
        if [[ -f "$cfg" ]]; then
            track "Final Configs" "$cfg" "pass"
        else
            track "Final Configs" "$cfg" "fail"
        fi
    done

    # Print all results grouped by category
    local pass=0
    local fail_count=0
    local warn_count=0
    local current_cat=""

    # Sort results by category for grouped display
    IFS=$'\n' sorted=($(sort <<<"${RESULTS[*]}")); unset IFS

    for entry in "${sorted[@]}"; do
        IFS='|' read -r cat name result <<< "$entry"

        if [[ "$cat" != "$current_cat" ]]; then
            echo ""
            printf "\033[1m%s:\033[0m\n" "$cat"
            current_cat="$cat"
        fi

        case "$result" in
            pass)
                printf "  \033[32m[OK]\033[0m   %s\n" "$name"
                ((pass++))
                ;;
            fail)
                printf "  \033[31m[FAIL]\033[0m %s\n" "$name"
                ((fail_count++))
                ;;
            warn)
                printf "  \033[33m[WARN]\033[0m %s\n" "$name"
                ((warn_count++))
                ;;
        esac
    done

    local total=$((pass + fail_count + warn_count))
    echo ""
    echo "========================================"
    printf "SUMMARY: %d/%d passed" "$pass" "$total"
    [[ $warn_count -gt 0 ]] && printf ", %d warnings" "$warn_count"
    [[ $fail_count -gt 0 ]] && printf ", %d failures" "$fail_count"
    echo ""
    echo "========================================"

    if [[ $fail_count -eq 0 ]]; then
        echo ""
        success "Bootstrap complete! Open a new terminal to start using fish."
    else
        echo ""
        warn "Some checks failed. Review output above and re-run failed phases."
        warn "Use: bash bootv4.sh --from-phase N"
    fi
}

# ============================================================================
# Main Execution — Run Phases
# ============================================================================
echo ""
echo "============================================"
echo "  bootv4 — macOS Bootstrap"
echo "  User: $CURRENT_USER   Host: $HOSTNAME"
echo "  Starting from phase: $START_PHASE"
echo "============================================"
echo ""

cleanup_legacy_state

run_phase 0 phase_0 || return 1
run_phase 1 phase_1 || return 1
run_phase 2 phase_2 || return 1
run_phase 3 phase_3 || return 1
run_phase 4 phase_4 || return 1
run_phase 5 phase_5 || return 1
run_phase 6 phase_6 || return 1
run_phase 7 phase_7 || return 1
run_phase 8 phase_8 || return 1
run_phase 9 phase_9 || return 1
run_phase 10 phase_10 || return 1

}  # end bootv4_main

bootv4_main "$@"
