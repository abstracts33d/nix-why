_:
let
  # Same dual-path recovery as the nixos/flake-parts adapters: real
  # darwin configs expose modules via `config._module.args.modules`,
  # but synthetic test fixtures built with plain lib.evalModules only
  # expose `_module` at the top level.
  recoverModules =
    darwinConfig:
    let
      fromConfig = builtins.tryEval (darwinConfig.config._module.args.modules or [ ]);
      fromTop = builtins.tryEval (darwinConfig._module.args.modules or [ ]);
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
  # adapt :: darwinConfiguration -> { modules, specialArgs, config, options }
  #
  # Extracts the uniform adapter record from a nix-darwin
  # darwinConfiguration (the result of lib.darwinSystem). Same opt-in
  # module recovery as the NixOS adapter.
  adapt = darwinConfig: {
    modules = recoverModules darwinConfig;
    specialArgs = { };
    config = darwinConfig.config or { };
    options = darwinConfig.options or { };
  };
}
