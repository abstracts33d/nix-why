{ lib }:
{
  modules = [
    {
      options.foo.items = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
        description = "test";
      };
    }
    {
      config.foo.items = lib.mkBefore [
        1
        2
      ];
    }
    { config.foo.items = [ 3 ]; }
  ];

  path = "foo.items";

  # mkBefore / mkAfter / mkOrder wrap a value as `{ _type = "order"; ... }`.
  # Pre-fix the walker did not unwrap "order", so the mkBefore definition's
  # value leaked the raw wrapper attrset instead of the list. Post-fix the
  # walk unwraps it; every definition's value is the underlying list.
  assertions =
    ast:
    ast.kind == "option"
    &&
      ast.value == [
        1
        2
        3
      ]
    && builtins.all (d: builtins.isList d.value) ast.definitions;
}
