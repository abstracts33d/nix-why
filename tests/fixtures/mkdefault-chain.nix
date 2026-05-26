{ lib }:
{
  modules = [
    {
      options.foo.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "test";
      };
    }
    { config.foo.enable = lib.mkDefault false; }
    { config.foo.enable = true; }
  ];

  path = "foo.enable";

  # The mkDefault (priority 1000) is overridden by the default (100).
  # Final value is true.
  assertions =
    ast:
    ast.kind == "option"
    && ast.value == true
    && ast.isDefined == true
    && ast.winningPriority == 100
    && (builtins.length ast.definitions) >= 2
    && (builtins.any (d: d.priorityKind == "mkDefault" && d.wins == false) ast.definitions)
    && (builtins.any (d: d.priorityKind == "default" && d.wins == true) ast.definitions);
}
