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

  # gate = false, so the mkIf-guarded def is filtered out. Final value
  # is the declared default.
  assertions = ast: ast.kind == "option" && ast.value == false && ast.isDefined == false;
}
