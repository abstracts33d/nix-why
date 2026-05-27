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
in
if mode == "search" then
  nixWhy.search {
    inherit (adapted) options;
    pattern = searchPattern;
    limit = lib.toInt searchLimit;
  }
else if mode == "whatSets" then
  nixWhy.whatSets {
    inherit (adapted) modules options config;
    path = optionPath;
  }
else if mode == "whyNot" then
  nixWhy.whyNot {
    inherit (adapted) modules options config;
    path = optionPath;
  }
else
  nixWhy.resolve {
    inherit (adapted) modules options config;
    path = optionPath;
  }
