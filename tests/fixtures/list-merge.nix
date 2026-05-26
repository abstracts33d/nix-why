{ lib }:
{
  modules = [
    {
      options.foo.list = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "test";
      };
    }
    { config.foo.list = [ "a" ]; }
    { config.foo.list = [ "b" ]; }
    { config.foo.list = [ "c" ]; }
  ];

  path = "foo.list";

  # List type with three contributing definitions; all should appear in
  # ast.definitions with wins=true.
  assertions =
    ast:
    ast.kind == "option" && (builtins.length ast.value) == 3 && (builtins.length ast.definitions) >= 3;
}
