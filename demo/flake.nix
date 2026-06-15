# Self-contained demo configuration for nix-why. Small on purpose: a flat
# module list so the opt-in `--full` module-walk resolves fully, and a story
# you can read in a few commands (a winner overriding a default, a merge
# conflict, an mkIf-gated option that never fires).
#
# Try it:
#   nix run github:abstracts33d/nix-why#option -- .#demo services.webapp.enable
#   nix run github:abstracts33d/nix-why#conflict -- .#demo services.webapp.port
#   nix run github:abstracts33d/nix-why#option -- --full why-not .#demo services.webapp.workers
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      # Wire the module list into _module.args.modules so `--full` can walk
      # it (the opt-in pattern a user adds to their own config).
      mkConfig =
        rawModules:
        let
          modules = rawModules ++ [ { config._module.args.modules = modules; } ];
        in
        lib.evalModules { inherit modules; };
    in
    {
      nixosConfigurations.demo = mkConfig [
        ./options.nix
        ./profile.nix
        ./host.nix
      ];
    };
}
