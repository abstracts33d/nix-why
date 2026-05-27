{ lib }:
{
  modules = [
    {
      options.foo.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "test";
      };
      options.gate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "test";
      };
    }
    (
      { config, ... }:
      {
        config.foo.enable = lib.mkIf config.gate true;
      }
    )
  ];

  path = "foo.enable";

  # gate = false, so the mkIf-guarded def is filtered out. Only the
  # option's declared default survives - NixOS treats `option.default`
  # as a definition at priority 1500 (mkOptionDefault), so isDefined
  # is true and the final value is the default `false`.
  assertions =
    ast:
    ast.kind == "option" && ast.value == false && ast.winningPriority == 1500;
}
