/**
  Adapter facade: map a flake's evaluated configuration shape onto
  the nix-why library's uniform `{ modules, specialArgs, config,
  options }` contract.

  Supported schemas:

  - `nixos`         — `lib.nixosSystem` / `lib.evalModules` with
                      the NixOS base modules
  - `home-manager`  — `homeConfigurations."<user>@<host>"`
  - `nix-darwin`    — `darwinConfigurations.<host>`
  - `flake-parts`   — `mkFlake` perSystem outputs or any plain
                      `lib.evalModules` result with `config` +
                      `options`
  - `raw`           — a directly-supplied `{ modules, specialArgs? }`
                      pair (used by `nix-why-option eval`)

  # Module recovery

  None of these schemas expose the raw modules list by default.
  Consumers opt in by setting `_module.args.modules = <list>` in
  their configuration; adapters then read it from either
  `config._module.args.modules` (real configs) or top-level
  `_module.args.modules` (plain `lib.evalModules` consumers).
  Without this opt-in, module-walk introspection degrades to
  options-surface fidelity (no per-definition line numbers / guard
  records).
*/
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

  /**
    Adapt an evaluated flake output to the uniform nix-why
    contract.

    If `name` is provided, dispatches directly to that adapter
    (used by the CLI's `--adapter` flag). Otherwise runs the
    `detectAdapter` heuristic against the `flakeOutput` shape.

    Throws when no adapter can be selected; the CLI translates
    this to exit code 3 (flake target not found or wrong schema).

    # Type

    ```
    adapt :: {
      name ? null :: "nixos" | "home-manager" | "nix-darwin"
                   | "flake-parts" | "raw" | null,
      flakeOutput :: AttrSet,
    } -> {
      modules :: [Module],       # empty if the adapter could not
                                 # recover the modules list
      specialArgs :: AttrSet,    # may be empty for some adapters
      config :: AttrSet,
      options :: AttrSet,
    }
    ```
  */
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
