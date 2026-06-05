# Driver expression for nix-why-option's flake-target subcommands:
# default (resolve), what-sets, why-not, and search.
#
# Invoked as:
#   nix eval --impure --json -f resolve.nix \
#     --argstr libPath        <path>
#     --argstr flakeRef       <flake ref>
#     --argstr attr           <attribute path inside flake>
#     --argstr optionPath     <dotted option path>          (ignored for search)
#     --argstr searchPattern  <fuzzy pattern>               (search only)
#     --argstr searchLimit    <int as string>               (search only)
#     --argstr adapterName    <nixos|home-manager|...|"">   ("" = autodetect)
#     --argstr mode           <resolve|whatSets|whyNot|search>
{
  libPath,
  flakeRef,
  attr,
  optionPath ? "",
  searchPattern ? "",
  searchLimit ? "50",
  adapterName ? "",
  mode ? "resolve",
  walkModules ? "0",
}:
let
  inherit ((import <nixpkgs> { })) lib;
  nixWhy = import libPath { inherit lib; };
  common = import ./_common.nix { inherit lib; };

  flake = builtins.getFlake flakeRef;
  target = common.resolveAttr flake attr;

  adapted = nixWhy.adapters.adapt {
    name = if adapterName == "" then null else adapterName;
    flakeOutput = target;
  };

  # Default: options-surface only (modules = []) - robust, never applies
  # raw modules, so it cannot hit the uncatchable "missing required
  # argument" crash that walking specialArgs-dependent modules triggers.
  # `--full` (walkModules) opts into the raw module-walk for richer
  # per-definition provenance; best-effort, may error on deep configs.
  walkList = if walkModules == "1" then adapted.modules else [ ];

  result =
    if mode == "search" then
      nixWhy.search {
        inherit (adapted) options;
        pattern = searchPattern;
        limit = lib.toInt searchLimit;
      }
    else if mode == "whatSets" then
      nixWhy.whatSets {
        inherit (adapted) options config;
        modules = walkList;
        path = optionPath;
      }
    else if mode == "whyNot" then
      nixWhy.whyNot {
        inherit (adapted) options config;
        modules = walkList;
        path = optionPath;
      }
    else
      nixWhy.resolve {
        inherit (adapted) options config;
        modules = walkList;
        path = optionPath;
      };
in
{ inherit (common) schemaVersion; } // result
