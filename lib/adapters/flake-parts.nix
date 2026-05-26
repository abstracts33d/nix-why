{ lib }:
{
  # adapt :: flakePartsOutput -> { modules, specialArgs, config, options }
  #
  # Extracts adapter inputs from a flake-parts perSystem evalModules
  # invocation. Implemented in commit 12.
  adapt = flakePartsOutput: {
    modules = [ ];
    specialArgs = { };
    config = flakePartsOutput.config or { };
    options = flakePartsOutput.options or { };
  };
}
