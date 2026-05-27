_:
let
  # flake-parts wraps lib.evalModules; the user typically points us at
  # either:
  #   - the perSystem evalModules result for a given system, or
  #   - a top-level evalModules invocation done by their own mkFlake
  #     wrapper.
  #
  # Both shapes expose { config, options }; module recovery follows the
  # same opt-in pattern as the NixOS-family adapters.
  # lib.evalModules exposes _module at the top of its result, but
  # `config._module` is only an attribute when the user (or nixpkgs)
  # declares `_module` as an option. We try both shapes so the adapter
  # works for plain lib.evalModules consumers (synthetic test flake)
  # and for flake-parts mkFlake setups that declare _module as an
  # option.
  recoverModules =
    flakePartsOutput:
    let
      fromConfig = builtins.tryEval (flakePartsOutput.config._module.args.modules or [ ]);
      fromTop = builtins.tryEval (flakePartsOutput._module.args.modules or [ ]);
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
  # adapt :: flakePartsEvalResult -> { modules, specialArgs, config, options }
  adapt = flakePartsOutput: {
    modules = recoverModules flakePartsOutput;
    specialArgs = { };
    config = flakePartsOutput.config or { };
    options = flakePartsOutput.options or { };
  };
}
