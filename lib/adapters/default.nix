{ lib }:
let
  nixos = import ./nixos.nix { inherit lib; };
  home-manager = import ./home-manager.nix { inherit lib; };
  nix-darwin = import ./nix-darwin.nix { inherit lib; };
  flake-parts = import ./flake-parts.nix { inherit lib; };
  raw = import ./raw.nix { inherit lib; };

  byName = {
    nixos = nixos.adapt;
    home-manager = home-manager.adapt;
    nix-darwin = nix-darwin.adapt;
    flake-parts = flake-parts.adapt;
    raw = raw.adapt;
  };
in
{
  inherit byName;

  # adapt :: { name, flakeOutput } -> { modules, specialArgs, config, options }
  #
  # Dispatches to the named adapter. Autodetection from a flake output's
  # shape (without an explicit name) is implemented in commit 13.
  adapt =
    {
      name,
      flakeOutput,
    }:
    if byName ? ${name} then
      byName.${name} flakeOutput
    else
      throw "nix-why: unknown adapter '${name}'. Available: ${lib.concatStringsSep ", " (lib.attrNames byName)}";
}
