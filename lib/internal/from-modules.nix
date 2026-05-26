{ lib }:
{
  # fromModules :: { modules, specialArgs, config, pathParts } -> { definitions }
  #
  # Walks the raw module list independently of the evaluated options
  # surface to recover per-definition priority kinds, line numbers via
  # builtins.unsafeGetAttrPos, and definitions filtered out by mkIf
  # evaluating false. This is the internal-coupled half of the hybrid
  # evaluation strategy. Implemented in commit 6.
  fromModules =
    {
      modules,
      specialArgs ? { },
      config ? { },
      pathParts,
    }:
    {
      definitions = [ ];
    };
}
