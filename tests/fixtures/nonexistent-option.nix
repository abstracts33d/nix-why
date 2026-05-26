{ lib }:
{
  modules = [
    {
      options.foo.bar = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "test";
      };
    }
  ];

  path = "does.not.exist";

  # Path does not resolve to any option (or even any attribute) in the
  # options tree. The library should report kind="not-found" and produce
  # an empty definitions list, not crash.
  assertions = ast: ast.kind == "not-found" && ast.definitions == [ ];
}
