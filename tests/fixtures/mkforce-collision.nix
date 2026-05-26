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
    { config.foo.enable = lib.mkForce true; }
    { config.foo.enable = lib.mkForce false; }
  ];

  path = "foo.enable";

  # Two mkForce (priority 50) on different values for an atomic type:
  # the module-system merge throws on this. valueError captures the
  # failure and the AST exposes a conflicts[] entry.
  assertions =
    ast:
    ast.kind == "option"
    && ast.value == null
    && ast.valueError != null
    && (builtins.length ast.conflicts) >= 1
    && (builtins.head ast.conflicts).kind == "merge-conflict";
}
