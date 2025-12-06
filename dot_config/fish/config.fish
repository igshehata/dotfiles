/opt/homebrew/bin/brew shellenv | source
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

    alias ci 'code-insiders'
    alias ag 'agy'
    alias ?? 'aichat'
    alias ls 'eza -l --no-permissions --icons --git'
    alias ll 'eza -la --no-permissions --icons --git'
    alias la 'eza -a --icons --git'
    alias lt 'eza -T --no-permissions --icons --level=2 --git'
    alias llt 'eza -lT --no-permissions --icons --level=2 --git'

    # Python aliases
    alias py=python3
    alias pip=pip3
end
