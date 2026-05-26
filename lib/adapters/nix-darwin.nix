{ lib }:
let
  recoverModules =
    darwinConfig:
    let
      tried = builtins.tryEval (darwinConfig.config._module.args.modules or [ ]);
    in
    if tried.success && builtins.isList tried.value then tried.value else [ ];
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
