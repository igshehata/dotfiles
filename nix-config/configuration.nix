{ pkgs, ... }:

{
  # Nix packages (CLI tools) — moved to homebrew.brews for portability
  environment.systemPackages = with pkgs; [];

  # Homebrew integration
  homebrew = {
    enable = true;
    user = "islam.shehata";  # Run Homebrew as user, not root
    onActivation = {
      autoUpdate = false;
      cleanup = "none";  # Safe mode - won't remove existing packages
      upgrade = false;
    };

    taps = [
      # homebrew/cask-fonts deprecated - fonts now in main cask
    ];

    # CLI tools (keeping in brew for now, can migrate to nix later)
    brews = [
      "mise"      "direnv"      "aichat"
      "atuin"
      "bash"
      "biome"
      "oven-sh/bun/bun"
      "carapace"
      "chezmoi"
      "commitizen"
      "difftastic"
      "eza"
      "fd"
      "ffmpeg"
      "fish"
      "fnm"
      "fzf"
      "gemini-cli"
      "gh"
      "gnupg"
      "go"
      "jq"
      "k6"
      "kind"
      "lua"
      "luajit"
      "node"
      "nushell"
      "openjdk"
      "pinentry"
      "pnpm"
      "python@3.13"
      "starship"
      "tmux"
      "tree"
      "zoxide"
      "opencode"
      "zig"
      "neofetch"
      "pandoc"
      "trivy"
      "yazi"
      "ripgrep"
      "bat"
      "neovim"
      "television"
      "rustup"
    ];

    # GUI apps
    casks = [
      "superwhisper"
      "1password"
      "1password-cli"
      "antigravity"
      "apidog"
      "arc"
      "discord"
      "ghostty"
      "google-chrome"
      "obsidian"
      "postman"
      "raycast"
      "visual-studio-code@insiders"
      "wezterm"
      # Nerd Fonts
      "font-jetbrains-mono-nerd-font"
    ];
  };

  # Enable Touch ID for sudo (reattach enables it inside tmux/screen)
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };

  # Shell configuration
  programs.fish.enable = true;
  programs.zsh.enable = true;
  # nushell installed via brew, config managed by chezmoi

  # Default shell (fish)
  environment.shells = [ pkgs.fish ];
  users.users."islam.shehata" = {
    shell = pkgs.fish;
  };

  # macOS System Defaults
  system.defaults = {
    dock.autohide = true;
  };

  # Nix settings
  nix.settings = {
    experimental-features = "nix-command flakes";
  };

  # Required
  ids.gids.nixbld = 350;  # Determinate installer uses 350, not 30000
  system.primaryUser = "islam.shehata";
  system.stateVersion = 4;
  nixpkgs.hostPlatform = "aarch64-darwin";
}
