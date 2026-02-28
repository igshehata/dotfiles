#!/usr/bin/env bash
# bootv4 — macOS bootstrap (curl|bash safe)
# Wrap everything in a function so bash parses the entire pipe before executing.
bootv4_main() {

set -uo pipefail
# NO set -e — we check return codes explicitly

# ============================================================================
# Configuration
# ============================================================================
STATE_FILE="$HOME/.bootv4-state"
CHEZMOI_SOURCE="$HOME/.local/share/chezmoi"
NIX_CONFIG="$HOME/nix-config"
DOTFILES_REPO="https://github.com/igshehata/dotfiles.git"
CURRENT_USER="$(whoami)"
HOSTNAME="$(hostname -s)"
START_PHASE=0

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

phase_done()   { grep -qx "$1" "$STATE_FILE" 2>/dev/null; }
mark_done()    { echo "$1" >> "$STATE_FILE"; }

# Result tracking for Phase 10 verification
RESULTS=()
track() { RESULTS+=("$1|$2|$3"); }  # category|name|pass/fail

should_run() {
    local phase_num="$1"
    [[ "$phase_num" -ge "$START_PHASE" ]]
}

# When --from-phase is used, clear state for those phases so they actually re-run
if [[ "$START_PHASE" -gt 0 ]]; then
    if [[ -f "$STATE_FILE" ]]; then
        for i in $(seq "$START_PHASE" 10); do
            sed -i '' "/^phase_${i}$/d" "$STATE_FILE" 2>/dev/null || true
        done
    fi
fi

# ============================================================================
# Phase 0: Prerequisites (Xcode CLT)
# ============================================================================
phase_0() {
    info "Phase 0: Xcode Command Line Tools"

    if xcode-select -p &>/dev/null; then
        skip "Xcode CLT already installed"
        mark_done "phase_0"
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
    mark_done "phase_0"
}

# ============================================================================
# Phase 1: Nix (Determinate installer)
# ============================================================================
phase_1() {
    info "Phase 1: Nix"

    if command -v nix &>/dev/null; then
        skip "Nix already installed ($(nix --version))"
        mark_done "phase_1"
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
        mark_done "phase_1"
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
        mark_done "phase_2"
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
        mark_done "phase_2"
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

    # Copy nix-config from chezmoi source if not already present
    if [[ ! -d "$NIX_CONFIG" ]]; then
        info "Copying nix-config from chezmoi source..."
        cp -r "$CHEZMOI_SOURCE/nix-config" "$NIX_CONFIG"
    fi

    local config_nix="$NIX_CONFIG/configuration.nix"
    local flake_nix="$NIX_CONFIG/flake.nix"

    # 1. homebrew.user in configuration.nix
    if grep -q "user = \"$CURRENT_USER\"" "$config_nix"; then
        skip "homebrew.user already set to $CURRENT_USER"
    else
        local old_user
        old_user=$(grep -oP 'user = "\K[^"]+' "$config_nix" | head -1)
        sed -i '' "s/user = \"$old_user\"/user = \"$CURRENT_USER\"/" "$config_nix"
        success "homebrew.user: $old_user -> $CURRENT_USER"
    fi

    # 2. users.users."..." in configuration.nix
    if grep -q "users.users.\"$CURRENT_USER\"" "$config_nix"; then
        skip "users.users already set to $CURRENT_USER"
    else
        local old_nix_user
        old_nix_user=$(grep -oP 'users\.users\.\"\K[^"]+' "$config_nix" | head -1)
        sed -i '' "s/users.users.\"$old_nix_user\"/users.users.\"$CURRENT_USER\"/" "$config_nix"
        success "users.users: $old_nix_user -> $CURRENT_USER"
    fi

    # 3. system.primaryUser in configuration.nix
    if grep -q "system.primaryUser = \"$CURRENT_USER\"" "$config_nix"; then
        skip "system.primaryUser already set to $CURRENT_USER"
    else
        local old_primary
        old_primary=$(grep -oP 'system\.primaryUser = "\K[^"]+' "$config_nix" | head -1)
        sed -i '' "s/system.primaryUser = \"$old_primary\"/system.primaryUser = \"$CURRENT_USER\"/" "$config_nix"
        success "system.primaryUser: $old_primary -> $CURRENT_USER"
    fi

    # 4. darwinConfigurations."..." in flake.nix
    if grep -q "darwinConfigurations.\"$HOSTNAME\"" "$flake_nix"; then
        skip "darwinConfigurations already set to $HOSTNAME"
    else
        local old_host
        old_host=$(grep -oP 'darwinConfigurations\."\K[^"]+' "$flake_nix" | head -1)
        sed -i '' "s/darwinConfigurations.\"$old_host\"/darwinConfigurations.\"$HOSTNAME\"/" "$flake_nix"
        success "darwinConfigurations: $old_host -> $HOSTNAME"
    fi

    mark_done "phase_3"
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
        brew update
        info "Upgrading existing packages..."
        brew upgrade
    fi

    info "Running darwin-rebuild switch --flake ~/nix-config#$HOSTNAME ..."
    sudo darwin-rebuild switch --flake "$NIX_CONFIG#$HOSTNAME" </dev/tty
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

    # Verify packages
    info "Verifying brew packages..."
    local brews=(
        mise direnv aichat atuin bash biome carapace chezmoi commitizen
        difftastic eza fd ffmpeg fish fnm fzf gemini-cli gh gnupg go jq
        k6 kind lua luajit node nushell openjdk pinentry pnpm starship
        tmux tree zoxide opencode zig neofetch pandoc trivy yazi ripgrep
        bat neovim television rustup
    )
    # oven-sh/bun/bun checked separately as "bun"
    brews+=("bun")
    # python@3.13 checked as "python@3.13"
    brews+=("python@3.13")

    for pkg in "${brews[@]}"; do
        if brew list --formula "$pkg" &>/dev/null; then
            track "Brews" "$pkg" "pass"
        else
            track "Brews" "$pkg" "fail"
            warn "Brew not found: $pkg"
        fi
    done

    local casks=(
        superwhisper 1password 1password-cli antigravity apidog arc
        discord ghostty google-chrome obsidian postman raycast
        visual-studio-code@insiders wezterm font-jetbrains-mono-nerd-font
    )

    for cask in "${casks[@]}"; do
        if brew list --cask "$cask" &>/dev/null; then
            track "Casks" "$cask" "pass"
        else
            track "Casks" "$cask" "fail"
            warn "Cask not found: $cask"
        fi
    done

    mark_done "phase_4"
}

# ============================================================================
# Phase 5: 1Password CLI setup
# ============================================================================
phase_5() {
    info "Phase 5: 1Password CLI"

    if op whoami &>/dev/null; then
        skip "1Password CLI already signed in"
        mark_done "phase_5"
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

    mark_done "phase_5"
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

    # Verify key deployed files
    local configs=(
        "$HOME/.config/fish/config.fish"
        "$HOME/.config/tmux/tmux.conf"
        "$HOME/.config/atuin/config.toml"
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
        key_line=$(grep '^key' "$HOME/.config/atuin/config.toml" 2>/dev/null || true)
        if [[ -n "$key_line" && ! "$key_line" =~ \{\{ ]]; then
            track "Configs" "atuin sync_key" "pass"
        else
            track "Configs" "atuin sync_key" "fail"
            warn "Atuin config missing sync key or has template placeholder"
        fi
    fi

    success "chezmoi apply completed"
    mark_done "phase_6"
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
                mark_done "phase_7"
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

    mark_done "phase_7"
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

    mark_done "phase_8"
}

# ============================================================================
# Phase 9: Atuin sync
# ============================================================================
phase_9() {
    info "Phase 9: Atuin sync"

    if ! command -v atuin &>/dev/null; then
        fail "atuin not found in PATH"
        return 1
    fi

    # Check if already logged in
    if atuin status 2>/dev/null | grep -q "session"; then
        skip "Atuin already logged in"
        info "Running force sync..."
        atuin sync -f
        success "Atuin synced"
        mark_done "phase_9"
        return 0
    fi

    # Extract sync key from chezmoi-deployed config
    local atuin_config="$HOME/.config/atuin/config.toml"
    local atuin_key=""

    if [[ -f "$atuin_config" ]]; then
        atuin_key=$(awk -F'"' '/^sync_key/{print $2}' "$atuin_config")
    fi

    # If key is missing or still a template placeholder, try re-running chezmoi
    # (the template needs 1Password CLI signed in to hydrate)
    if [[ -z "$atuin_key" || "$atuin_key" == *"{{"* || "$atuin_key" == *"onepassword"* ]]; then
        warn "Atuin sync key not hydrated — attempting chezmoi apply for atuin config..."
        if op whoami &>/dev/null; then
            chezmoi apply "$HOME/.config/atuin/config.toml" </dev/tty 2>/dev/null
            atuin_key=$(awk -F'"' '/^sync_key/{print $2}' "$atuin_config")
        else
            warn "1Password CLI not signed in — cannot hydrate atuin sync key"
        fi
    fi

    if [[ -z "$atuin_key" || "$atuin_key" == *"{{"* || "$atuin_key" == *"onepassword"* ]]; then
        fail "No valid atuin sync key — sign into 1Password (Phase 5) and re-run: bash bootv4.sh --from-phase 9"
        mark_done "phase_9"
        return 0
    fi

    info "Atuin sync key found in config"

    local atuin_user
    printf "Atuin username: " >/dev/tty
    tty_read -r atuin_user

    info "Logging into atuin (will prompt for password)..."
    atuin login -u "$atuin_user" -k "$atuin_key" </dev/tty
    local login_rc=$?

    if [[ $login_rc -ne 0 ]]; then
        warn "Atuin login failed (exit $login_rc)"
        mark_done "phase_9"
        return 0
    fi

    info "Running force sync..."
    atuin sync -f

    if atuin status 2>/dev/null | grep -q "session"; then
        success "Atuin synced"
        track "Shell" "atuin sync" "pass"
    else
        warn "Atuin sync may have issues"
        track "Shell" "atuin sync" "fail"
    fi

    mark_done "phase_9"
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
        "nvim:nvim"
        "tmux:tmux"
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
        "$HOME/.gitconfig"
    )

    for cfg in "${config_checks[@]}"; do
        if [[ -f "$cfg" ]]; then
            track "Final Configs" "$(basename "$cfg")" "pass"
        else
            track "Final Configs" "$(basename "$cfg")" "fail"
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

should_run 0  && { phase_done "phase_0"  || phase_0;  }
should_run 1  && { phase_done "phase_1"  || phase_1;  }
should_run 2  && { phase_done "phase_2"  || phase_2;  }
should_run 3  && { phase_done "phase_3"  || phase_3;  }
should_run 4  && { phase_done "phase_4"  || phase_4;  }
should_run 5  && { phase_done "phase_5"  || phase_5;  }
should_run 6  && { phase_done "phase_6"  || phase_6;  }
should_run 7  && { phase_done "phase_7"  || phase_7;  }
should_run 8  && { phase_done "phase_8"  || phase_8;  }
should_run 9  && { phase_done "phase_9"  || phase_9;  }
should_run 10 && phase_10

}  # end bootv4_main

bootv4_main "$@"
