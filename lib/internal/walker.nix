{ lib }:
{
  # walkConfig :: { config, pathParts } -> [{ kind, value, ... }]
  #
  # Walk a module config tree along `pathParts`, classifying each
  # intermediate node by its `_type` marker (mkIf / mkOverride / mkMerge).
  # Returns the list of leaf records found at the path. Implemented in
  # commit 4.
  walkConfig =
    {
      config,
      pathParts,
    }:
    [ ];
}
