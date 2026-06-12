# Driver expression for the `eval` subcommand of nix-why-option.
#
# The user's arbitrary Nix expression is written to a file by the CLI
# and the path is passed in via --argstr. We `import` that file - no
# shell-side interpolation into Nix syntax is required, eliminating
# an entire class of escape bugs.
#
# Invoked as:
#   nix eval --impure --json -f eval.nix \
#     --argstr libPath        <path to nix-why lib>
#     --argstr userExprFile   <path to a .nix file containing the user expr>
#     --argstr optionPath     <dotted option path>
#     --argstr adapterName    <name | "">
#     --argstr mode           <resolve|whatSets|whyNot|search>
#     --argstr searchPattern  <fuzzy pattern>
#     --argstr searchLimit    <int as string>
{
  libPath,
  userExprFile,
  optionPath ? "",
  searchPattern ? "",
  searchLimit ? "50",
  adapterName ? "",
  mode ? "resolve",
}:
let
  # No flake in scope for the eval subcommand; lib-only import avoids
  # instantiating the pkgs fixpoint.
  lib = import <nixpkgs/lib>;
  nixWhy = import libPath { inherit lib; };
  common = import ./_common.nix { inherit lib; };

  userResult = import userExprFile;

  # If the user supplied { modules, specialArgs? } directly, dispatch
  # via the raw adapter (runs evalModules on those modules). Otherwise
  # treat the result as an already-evaluated flake output and let
  # autodetect work.
  isRawInput = builtins.isAttrs userResult && (userResult ? modules);

  adapted =
    if adapterName == "raw" || isRawInput then
      nixWhy.adapters.byName.raw userResult
    else
      nixWhy.adapters.adapt {
        name = if adapterName == "" then null else adapterName;
        flakeOutput = userResult;
      };

  result =
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
      };
in
{ inherit (common) schemaVersion; } // result
