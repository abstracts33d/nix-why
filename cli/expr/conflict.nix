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
  walkModules ? "0",
}:
let
  flake = builtins.getFlake flakeRef;

  # Same lib-threading as resolve.nix: target flake's own nixpkgs lib
  # first, <nixpkgs/lib> fallback.
  lib = flake.inputs.nixpkgs.lib or (import <nixpkgs/lib>);
  nixWhy = import libPath { inherit lib; };
  common = import ./_common.nix { inherit lib; };

  target = common.resolveAttr flake attr;

  adapted = nixWhy.adapters.adapt {
    name = if adapterName == "" then null else adapterName;
    flakeOutput = target;
  };

  # Same gate as resolve.nix: options-surface by default. Walking raw
  # modules re-applies function modules that may need unavailable
  # specialArgs, which aborts uncatchably; conflicts are detected on
  # the surface path (tryEval of the merged value) regardless.
  walkList = if walkModules == "1" then adapted.modules else [ ];

  ast = nixWhy.resolve {
    inherit (adapted) options config;
    modules = walkList;
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
