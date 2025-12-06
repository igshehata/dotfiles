{ pkgs, ... }:

{
  # Nix packages (CLI tools)
  environment.systemPackages = with pkgs; [
    git
    neovim
  ];

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
      "aichat"
      "atuin"
      "bash"
      "bat"
      "biome"
      "bun"
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
      "neovim"
      "node"
      "nushell"
      "openjdk"
      "pinentry"
      "pnpm"
      "python@3.13"
      "ripgrep"
      "starship"
      "tmux"
      "tree"
      "yazi"
      "zoxide"
    ];

    # GUI apps
    casks = [
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
      "font-3270-nerd-font"
      "font-agave-nerd-font"
      "font-anonymice-nerd-font"
      "font-arimo-nerd-font"
      "font-aurulent-sans-mono-nerd-font"
      "font-bigblue-terminal-nerd-font"
      "font-bitstream-vera-sans-mono-nerd-font"
      "font-blex-mono-nerd-font"
      "font-caskaydia-cove-nerd-font"
      "font-caskaydia-mono-nerd-font"
      "font-code-new-roman-nerd-font"
      "font-comic-shanns-mono-nerd-font"
      "font-commit-mono-nerd-font"
      "font-cousine-nerd-font"
      "font-d2coding-nerd-font"
      "font-daddy-time-mono-nerd-font"
      "font-dejavu-sans-mono-nerd-font"
      "font-droid-sans-mono-nerd-font"
      "font-envy-code-r-nerd-font"
      "font-fantasque-sans-mono-nerd-font"
      "font-fira-code-nerd-font"
      "font-fira-mono-nerd-font"
      "font-geist-mono-nerd-font"
      "font-go-mono-nerd-font"
      "font-gohufont-nerd-font"
      "font-hack-nerd-font"
      "font-hasklug-nerd-font"
      "font-heavy-data-nerd-font"
      "font-hurmit-nerd-font"
      "font-im-writing-nerd-font"
      "font-inconsolata-go-nerd-font"
      "font-inconsolata-lgc-nerd-font"
      "font-inconsolata-nerd-font"
      "font-intone-mono-nerd-font"
      "font-iosevka-nerd-font"
      "font-iosevka-term-nerd-font"
      "font-iosevka-term-slab-nerd-font"
      "font-jetbrains-mono-nerd-font"
      "font-lekton-nerd-font"
      "font-liberation-nerd-font"
      "font-lilex-nerd-font"
      "font-m+-nerd-font"
      "font-martian-mono-nerd-font"
      "font-monaspice-nerd-font"
      "font-monocraft-nerd-font"
      "font-monofur-nerd-font"
      "font-monoid-nerd-font"
      "font-mononoki-nerd-font"
      "font-noto-nerd-font"
      "font-opendyslexic-nerd-font"
      "font-overpass-nerd-font"
      "font-profont-nerd-font"
      "font-proggy-clean-tt-nerd-font"
      "font-roboto-mono-nerd-font"
      "font-sauce-code-pro-nerd-font"
      "font-shure-tech-mono-nerd-font"
      "font-space-mono-nerd-font"
      "font-symbols-only-nerd-font"
      "font-terminess-ttf-nerd-font"
      "font-tinos-nerd-font"
      "font-ubuntu-mono-nerd-font"
      "font-ubuntu-nerd-font"
      "font-ubuntu-sans-nerd-font"
      "font-victor-mono-nerd-font"
      "font-zed-mono-nerd-font"
    ];
  };

  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

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
