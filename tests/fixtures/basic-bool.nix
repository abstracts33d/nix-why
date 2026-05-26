{ lib }:
{
  modules = [
    {
      options.foo.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "test";
      };
      config.foo.enable = true;
    }
  ];

  path = "foo.enable";

  # Single definition at default priority (100), value true.
  assertions =
    ast:
    ast.kind == "option"
    && ast.type == "bool"
    && ast.value == true
    && ast.isDefined == true
    && ast.winningPriority == 100
    && (builtins.length ast.definitions) >= 1
    && (builtins.head ast.definitions).wins == true;
}
