{ lib }:
{
  # Apply a function module with captured args, without ever letting Nix
  # pattern-match blind.
  #
  # FOOTGUN: calling a function whose pattern lacks a required argument,
  # or passing an arg a strict (no-`...`) pattern does not declare, is a
  # hard EvalError that `builtins.tryEval` CANNOT catch - it aborts the
  # whole evaluation. Real flake modules take specialArgs (e.g.
  # `{ inputs, ... }`) that are absent from `config._module.args`, so a
  # blind `fn capturedArgs` aborts the walk on most real configs.
  #
  # So we gate on `builtins.functionArgs` first:
  #   - skip the module (return null) if any required formal is missing;
  #   - pass exactly declared-intersect-available, which a function body
  #     can always satisfy (it can only reference its declared formals),
  #     so the application never throws "unexpected argument".
  # The remaining tryEval guards only catchable throws in the module
  # body itself.
  applyFunctionModule =
    fn: capturedArgs:
    let
      argSpec = builtins.functionArgs fn;
      requiredMissing = lib.any (n: !(capturedArgs ? ${n})) (
        lib.attrNames (lib.filterAttrs (_: hasDefault: !hasDefault) argSpec)
      );
      callArgs = lib.filterAttrs (n: _: argSpec ? ${n}) capturedArgs;
    in
    if requiredMissing then
      null
    else
      let
        called = builtins.tryEval (fn callArgs);
      in
      if called.success then called.value else null;
}
