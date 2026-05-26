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
    { config.foo.enable = true; }
    { config.foo.enable = lib.mkForce false; }
  ];

  path = "foo.enable";

  # mkForce (priority 50) overrides the default (priority 100).
  # Final value is false; the mkForce def wins, the default def loses.
  assertions =
    ast:
    ast.kind == "option"
    && ast.value == false
    && ast.winningPriority == 50
    && (builtins.any (d: d.priorityKind == "mkForce" && d.wins == true) ast.definitions)
    && (builtins.any (d: d.priorityKind == "default" && d.wins == false) ast.definitions);
}
