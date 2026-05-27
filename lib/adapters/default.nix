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

  # Heuristic schema detection. Order matters: more specific shapes are
  # checked before more general ones.
  detectAdapter =
    flakeOutput:
    let
      has = path: lib.hasAttrByPath path flakeOutput;
    in
    if
      has [
        "config"
        "home"
        "homeDirectory"
      ]
      || has [ "activationPackage" ]
    then
      "home-manager"
    else if
      has [
        "config"
        "system"
        "defaults"
      ]
      || has [
        "system"
        "build"
        "darwin-system"
      ]
    then
      "nix-darwin"
    else if
      has [
        "config"
        "system"
        "build"
        "toplevel"
      ]
      || has [
        "config"
        "boot"
      ]
    then
      "nixos"
    else if has [ "config" ] && has [ "options" ] then
      "flake-parts"
    else
      null;
in
{
  inherit byName detectAdapter;

  # adapt :: { name ? null, flakeOutput } -> { modules, specialArgs, config, options }
  #
  # If `name` is provided, dispatches directly to that adapter (used by
  # the CLI's --adapter flag). Otherwise runs the detection heuristic
  # against the flakeOutput shape.
  #
  # Throws when no adapter can be selected; the CLI translates this to
  # exit code 3 (flake target not found or wrong schema).
  adapt =
    {
      name ? null,
      flakeOutput,
    }:
    let
      chosen = if name != null then name else detectAdapter flakeOutput;
    in
    if chosen == null then
      throw "nix-why: could not detect adapter from flake output shape; pass --adapter <name>. Available: ${lib.concatStringsSep ", " (lib.attrNames byName)}"
    else if byName ? ${chosen} then
      byName.${chosen} flakeOutput
    else
      throw "nix-why: unknown adapter '${chosen}'. Available: ${lib.concatStringsSep ", " (lib.attrNames byName)}";
}
