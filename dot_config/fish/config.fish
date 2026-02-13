/opt/homebrew/bin/brew shellenv | source

# Nix darwin system binaries
fish_add_path /run/current-system/sw/bin

if status is-interactive
    # Enable vim mode
    fish_vi_key_bindings

    # Option+Backspace: delete word backward (works in vi insert mode)
    bind -M insert \e\x7f backward-kill-word
    # Command+Backspace: delete to start of line (works in vi insert mode)
    bind -M insert \cU backward-kill-line

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

    # Git push: Tab inserts "origin <current-branch>" directly (no escaped space)
    function _git_push_tab_complete
        set -l line (commandline --current-buffer)
        set -l cursor (commandline --cursor)
        set -l line_trim (string trim --right --chars ' ' -- $line)

        if test $cursor -eq (string length -- $line)
            if string match -qr '^(gp|git push)$' -- $line_trim
                set -l branch (command git branch --show-current 2>/dev/null)
                if test -n "$branch"
                    if test "$line_trim" = "gp"
                        commandline --replace "gp origin $branch"
                    else
                        commandline --replace "git push origin $branch"
                    end
                    commandline --cursor (string length -- (commandline --current-buffer))
                    return
                end
            end
        end

        commandline -f complete
    end

    bind -M insert \t _git_push_tab_complete
    bind -M default \t _git_push_tab_complete

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
        echo "Usage: nix <add|dedupe> [--brew|--cask] [packages...]"
        return 1
    end

    set subcommand $argv[1]
    set packages $argv[2..-1]
    set config_file ~/nix-config/configuration.nix

    switch $subcommand
        case add
            # Parse flags
            set target nix
            set pkg_list

            for arg in $packages
                switch $arg
                    case --brew
                        set target brew
                    case --cask
                        set target cask
                    case '*'
                        set -a pkg_list $arg
                end
            end

            if test (count $pkg_list) -lt 1
                echo "Usage: nix add [--brew|--cask] <package1> [package2] ..."
                echo "  (default)  Add to nix packages"
                echo "  --brew     Add to Homebrew brews"
                echo "  --cask     Add to Homebrew casks"
                return 1
            end

            for pkg in $pkg_list
                switch $target
                    case nix
                        sed -i '' "/environment.systemPackages = with pkgs; \[/a\\
    $pkg" $config_file
                        echo "Added $pkg to nix packages"
                    case brew
                        sed -i '' "/brews = \[/a\\
      \"$pkg\"" $config_file
                        echo "Added $pkg to brews"
                    case cask
                        sed -i '' "/casks = \[/a\\
      \"$pkg\"" $config_file
                        echo "Added $pkg to casks"
                end
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
