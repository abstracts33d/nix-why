_:
let
  recoverModules =
    hmConfig:
    let
      tried = builtins.tryEval (hmConfig.config._module.args.modules or [ ]);
    in
    if tried.success && builtins.isList tried.value then tried.value else [ ];
in
{
  # adapt :: homeConfiguration -> { modules, specialArgs, config, options }
  #
  # Extracts the uniform adapter record from a home-manager
  # homeConfiguration (typically `homeConfigurations."user@host"`).
  #
  # Module recovery follows the same opt-in pattern as the NixOS
  # adapter: set _module.args.modules in the HM config to enable full
  # module-walk introspection.
  adapt = hmConfig: {
    modules = recoverModules hmConfig;
    specialArgs = { };
    config = hmConfig.config or { };
    options = hmConfig.options or { };
  };
}
