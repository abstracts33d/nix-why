{ lib }:
{
  # adapt :: { modules, specialArgs ? {} } -> { modules, specialArgs, config, options }
  #
  # Power-user adapter: accepts an explicit { modules, specialArgs }
  # record, runs lib.evalModules itself, and returns the result. Used by
  # the `eval` subcommand. Implemented in commit 12.
  adapt =
    {
      modules,
      specialArgs ? { },
    }:
    let
      eval = lib.evalModules {
        inherit modules;
        inherit specialArgs;
      };
    in
    {
      inherit modules specialArgs;
      inherit (eval) config options;
    };
}
