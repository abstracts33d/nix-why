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
    { config.foo.enable = lib.mkOverride 200 true; }
  ];

  path = "foo.enable";

  # mkOverride with an unnamed priority (200). The label should fall back
  # to the literal "mkOverride 200" form.
  assertions =
    ast:
    ast.kind == "option"
    && ast.value == true
    && ast.winningPriority == 200
    && (builtins.any (d: d.priorityKind == "mkOverride 200") ast.definitions);
}
