{ pkgs, ... }:

{
  # Linux servers (the Contabo VPS), applied by system-manager on top of Ubuntu
  # with `sms`. It manages only what is declared here: packages
  # (/run/system-manager/sw/bin), /etc files (environment.etc) and systemd
  # units (systemd.services). apt keeps the kernel, boot and everything else.
  # Same split as the Mac: CLI tools in ~/.Brewfile, languages in mise.
  #
  # Existing /etc files are never overwritten unless the entry sets
  # replaceExisting = true. There is no rollback command yet: change
  # /etc/ssh or networking only with a second SSH session open, and keep the
  # Contabo VNC console as the fallback.

  # Nix packages (escape hatch)
  environment.systemPackages = with pkgs; [
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
}
