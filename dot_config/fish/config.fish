/opt/homebrew/bin/brew shellenv | source

# Nix darwin system binaries
fish_add_path /run/current-system/sw/bin

if status is-interactive
    # Enable vim mode
    fish_vi_key_bindings

    fnm env --use-on-cd | source

    # add to ~/.config/fish/config.fish
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    # Initialize starship prompt
    starship init fish | source

    # Initialize atuin (history sync)
    atuin init fish | source

    # Configure transient prompt - shows only character module
    function starship_transient_prompt_func
        starship module character
    end

    # Configure right-side transient prompt - shows time module
    function starship_transient_rprompt_func
        starship module time
    end

    # Enable transient prompt mode
    enable_transience

    # Initialize zoxide
    zoxide init fish | source
    # Set up fzf key bindings (disabled - using television for ctrl+t instead)
    # fzf --fish | source
    # Initialize carapace completions
    carapace _carapace | source

    alias ci code-insiders
    alias nv nvim
    alias ?? aichat
    alias ls 'eza -l --no-permissions --icons --git'
    alias ll 'eza -la --no-permissions --icons --git'
    alias la 'eza -a --icons --git'
    alias lt 'eza -T --no-permissions --icons --level=2 --git'
    alias llt 'eza -lT --no-permissions --icons --level=2 --git'

    # Python aliases
    alias py=python3
    alias pip=pip3

    # Nix darwin (requires sudo since May 2025 - Phase 1 of multi-user support)
    abbr --add drs 'sudo darwin-rebuild switch --flake ~/nix-config#igshehata'
end

# nix add/dedupe - Nix configuration helpers
function nix
    if test (count $argv) -lt 1
        echo "Usage: nix <add|dedupe> [packages...]"
        return 1
    end

    set subcommand $argv[1]
    set packages $argv[2..-1]
    set config_file ~/nix-config/configuration.nix

    switch $subcommand
        case add
            if test (count $packages) -lt 1
                echo "Usage: nix add <package1> [package2] ..."
                return 1
            end

            for pkg in $packages
                sed -i '' "/environment.systemPackages = with pkgs; \[/a\\
    $pkg" $config_file
                echo "Added $pkg to configuration.nix"
            end

            echo ""
            echo "Next: drs && chezmoi re-add ~/nix-config/configuration.nix"

        case dedupe
            # Extract nix packages (between systemPackages = [ and ];)
            set nix_pkgs (sed -n '/environment.systemPackages/,/\];/p' $config_file | grep -oE '^\s+\w+' | tr -d ' ')

            # Extract brews (between brews = [ and ];)
            set brews (sed -n '/brews = \[/,/\];/p' $config_file | grep -oE '"[^"]+"' | tr -d '"')

            set found 0
            for pkg in $nix_pkgs
                if contains $pkg $brews
                    sed -i '' "/brews = \[/,/\];/{ /\"$pkg\"/d; }" $config_file
                    echo "Removed '$pkg' from brews (exists in nix packages)"
                    set found (math $found + 1)
                end
            end

            if test $found -eq 0
                echo "No duplicates found"
            else
                echo ""
                echo "Removed $found duplicate(s)"
                echo "Next: drs && chezmoi re-add ~/nix-config/configuration.nix"
            end

        case '*'
            # Pass through to actual nix command
            command nix $argv
    end
end
