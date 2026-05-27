# Synthetic flake used by tests/smoke/e2e.sh and tests/e2e.bats to
# exercise the nix-why CLIs end-to-end without depending on the
# author's actual fleet.
#
# Uses lib.evalModules directly (no NixOS bootstrap) so the eval is
# fast and the only input is nixpkgs.
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      # Wire the modules list back into _module.args.modules so the
      # nix-why module-walk pass can see it. This is the opt-in
      # pattern users do in their own configs to get full fidelity.
      mkSyntheticConfig =
        rawModules:
        let
          modules = rawModules ++ [
            { config._module.check = false; }
            { config._module.args.modules = modules; }
          ];
        in
        lib.evalModules { inherit modules; };
    in
    {
      nixosConfigurations.test = mkSyntheticConfig [
        ./modules/options.nix
        ./modules/config.nix
      ];

      nixosConfigurations.conflicting = mkSyntheticConfig [
        ./modules/options.nix
        ./modules/conflicting.nix
      ];
    };
}
