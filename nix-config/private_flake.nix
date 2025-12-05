{
  description = "Islam's macOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs }: {
    darwinConfigurations."igshehata" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [ ./configuration.nix ];
    };
  };
}
