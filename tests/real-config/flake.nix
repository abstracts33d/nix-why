# Real-config smoke fixture: an ACTUAL lib.nixosSystem across multiple
# nixpkgs releases. Driven by tests/smoke/real-config.sh (manual, not
# CI-gated - a full NixOS eval is heavy and the sandbox cannot lock
# nixpkgs). Catches internal-coupling drift and guards the regression
# where nix-why crashed applying specialArgs-dependent function modules.
{
  description = "nix-why real-config smoke fixture (actual lib.nixosSystem).";

  inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.nixpkgs-2411.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs =
    {
      nixpkgs-unstable,
      nixpkgs-2411,
      ...
    }:
    let
      mk =
        nixpkgs:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./configuration.nix ];
        };
    in
    {
      # Add releases here to widen the drift matrix; the smoke script
      # iterates every nixosConfigurations attr.
      nixosConfigurations = {
        unstable = mk nixpkgs-unstable;
        release-2411 = mk nixpkgs-2411;
      };
    };
}
