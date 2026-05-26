{ lib }:
let
  # flake-parts wraps lib.evalModules; the user typically points us at
  # either:
  #   - the perSystem evalModules result for a given system, or
  #   - a top-level evalModules invocation done by their own mkFlake
  #     wrapper.
  #
  # Both shapes expose { config, options }; module recovery follows the
  # same opt-in pattern as the NixOS-family adapters.
  recoverModules =
    flakePartsOutput:
    let
      tried = builtins.tryEval (flakePartsOutput.config._module.args.modules or [ ]);
    in
    if tried.success && builtins.isList tried.value then tried.value else [ ];
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
