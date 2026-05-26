{ lib }:
{
  # adapt :: darwinConfiguration -> { modules, specialArgs, config, options }
  #
  # Extracts adapter inputs from a nix-darwin darwinConfiguration.
  # Implemented in commit 11.
  adapt = darwinConfig: {
    modules = [ ];
    specialArgs = { };
    config = darwinConfig.config or { };
    options = darwinConfig.options or { };
  };
}
