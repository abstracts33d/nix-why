_:
let
  # Same dual-path recovery as the nixos/flake-parts adapters: real HM
  # configs expose modules via `config._module.args.modules`, but
  # synthetic test fixtures built with plain lib.evalModules only
  # expose `_module` at the top level.
  recoverModules =
    hmConfig:
    let
      fromConfig = builtins.tryEval (hmConfig.config._module.args.modules or [ ]);
      fromTop = builtins.tryEval (hmConfig._module.args.modules or [ ]);
      pick =
        if fromConfig.success && builtins.isList fromConfig.value && fromConfig.value != [ ] then
          fromConfig.value
        else if fromTop.success && builtins.isList fromTop.value then
          fromTop.value
        else
          [ ];
    in
    pick;
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
