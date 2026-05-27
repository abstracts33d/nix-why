# Shared helpers used by the cli/expr/*.nix files. Imported, not
# evaluated directly.
{ lib }:
let
  # Stable contract version for the JSON outputs emitted by the
  # nix-why-* CLIs (resolve, what-sets, why-not, search, conflict,
  # overlay-listing, overlay-attribution, recursion). Bumped on
  # breaking changes (field removed or semantics changed); additive
  # changes keep the same version.
  #
  # Documented at docs/reference/json-schema.md - read that before
  # bumping.
  schemaVersion = "1";

  schemas = [
    "nixosConfigurations"
    "darwinConfigurations"
    "homeConfigurations"
  ];

  # Resolve an attribute path against a flake, with optional schema
  # shorthand (".#krach" -> tries nixosConfigurations.krach,
  # darwinConfigurations.krach, homeConfigurations.krach in order;
  # errors on ambiguity or no match).
  resolveAttr =
    flake: attr:
    let
      parts = lib.splitString "." attr;
      headPart = builtins.head parts;
    in
    if attr == "" then
      throw "nix-why: no attribute path given after '#'"
    else if lib.elem headPart schemas then
      lib.attrByPath parts (throw "nix-why: attribute path '${attr}' not found in flake") flake
    else
      let
        tries = lib.filter (s: lib.hasAttrByPath ([ s ] ++ parts) flake) schemas;
      in
      if tries == [ ] then
        throw "nix-why: '${attr}' did not match any of ${lib.concatStringsSep ", " schemas} in the flake. Use the explicit form (e.g. .#nixosConfigurations.${attr})"
      else if (builtins.length tries) > 1 then
        throw "nix-why: '${attr}' is ambiguous - found under ${lib.concatStringsSep ", " tries}. Use the explicit form."
      else
        lib.attrByPath ([ (builtins.head tries) ] ++ parts) (throw "unreachable") flake;
in
{
  inherit schemaVersion schemas resolveAttr;
}
