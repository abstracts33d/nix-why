_:
let
  # Try to recover the raw modules list from a NixOS evaluated config.
  # NixOS does not expose this by default; the user (or their flake
  # framework) can opt-in by setting:
  #     _module.args.modules = <the modules list>
  # Without this opt-in, module-walk introspection degrades gracefully
  # to options-surface only.
  recoverModules =
    nixosConfig:
    let
      # NixOS proper exposes _module via its base modules so
      # `config._module.args.modules` works. Plain lib.evalModules
      # consumers don't get _module declared as an option, but the
      # eval-level _module is still accessible at the top of the
      # result. Try both shapes.
      fromConfig = builtins.tryEval (nixosConfig.config._module.args.modules or [ ]);
      fromTop = builtins.tryEval (nixosConfig._module.args.modules or [ ]);
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
  # adapt :: nixosConfiguration -> { modules, specialArgs, config, options }
  #
  # Extracts the uniform adapter record from a NixOS evaluated
  # configuration (the result of lib.nixosSystem / lib.evalModules with
  # the NixOS module set).
  #
  # specialArgs cannot be recovered from a post-evaluation NixOS
  # configuration; returned empty.
  adapt = nixosConfig: {
    modules = recoverModules nixosConfig;
    specialArgs = { };
    config = nixosConfig.config or { };
    options = nixosConfig.options or { };
  };
}
