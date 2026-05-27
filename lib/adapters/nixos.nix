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
      tried = builtins.tryEval (nixosConfig.config._module.args.modules or [ ]);
    in
    if tried.success && builtins.isList tried.value then tried.value else [ ];
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
