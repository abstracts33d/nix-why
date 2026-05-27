# Driver expression for nix-why-conflict. Runs the full resolve flow
# but returns only the conflict-shaped subset of the AST.
#
# Invoked as:
#   nix eval --impure --json -f conflict.nix \
#     --argstr libPath      <path to nix-why lib>
#     --argstr flakeRef     <flake ref>
#     --argstr attr         <attribute path>
#     --argstr optionPath   <dotted option path>
#     --argstr adapterName  <name | "">
{
  libPath,
  flakeRef,
  attr,
  optionPath,
  adapterName ? "",
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

  ast = nixWhy.resolve {
    inherit (adapted) modules options config;
    path = optionPath;
  };
in
{
  inherit (common) schemaVersion;
  inherit (ast)
    path
    kind
    type
    valueError
    conflicts
    ;
}
