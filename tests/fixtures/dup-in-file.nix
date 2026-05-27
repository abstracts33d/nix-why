{ lib }:
{
  modules = [
    {
      options.foo.list = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "test";
      };
      config = lib.mkMerge [
        { foo.list = [ "a" ]; }
        { foo.list = [ "b" ]; }
      ];
    }
  ];

  path = "foo.list";

  # Two definitions live in the same module but at different attribute
  # positions. The walker should distinguish them via unsafeGetAttrPos.
  assertions =
    ast:
    ast.kind == "option"
    &&
      ast.value == [
        "a"
        "b"
      ]
    && (builtins.length ast.definitions) >= 2;
}
