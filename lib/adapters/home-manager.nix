{ lib }:
{
  # adapt :: homeConfiguration -> { modules, specialArgs, config, options }
  #
  # Extracts adapter inputs from a home-manager homeConfiguration.
  # Implemented in commit 11.
  adapt = hmConfig: {
    modules = [ ];
    specialArgs = { };
    config = hmConfig.config or { };
    options = hmConfig.options or { };
  };
}
