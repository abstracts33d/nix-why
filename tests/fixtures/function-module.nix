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
    (_: {
      config.foo.enable = true;
    })
  ];

  path = "foo.enable";

  # Function module is now applied by from-modules.nix (not skipped).
  # The module-walk should produce at least one definition with
  # priority 100 from the function module's config attrset.
  assertions =
    ast:
    ast.kind == "option"
    && ast.value == true
    && ast.winningPriority == 100
    && (builtins.any (d: d.priority == 100 && d.wins == true) ast.definitions);
}
