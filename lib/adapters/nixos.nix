{ lib }:
{
  # adapt :: nixosConfiguration -> { modules, specialArgs, config, options }
  #
  # Extracts a uniform { modules, specialArgs, config, options } record
  # from a NixOS evaluated configuration. The raw modules list is
  # recovered via extendModules introspection. Implemented in commit 10.
  adapt = nixosConfig: {
    modules = [ ];
    specialArgs = { };
    config = nixosConfig.config or { };
    options = nixosConfig.options or { };
  };
}
