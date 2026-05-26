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
    {
      config.foo.list = lib.mkMerge [
        [ "a" ]
        [ "b" ]
        [ "c" ]
      ];
    }
  ];

  path = "foo.list";

  # mkMerge fans the three list values out; the merged result is their
  # concatenation in order.
  assertions = ast: ast.kind == "option" && ast.value == [ "a" "b" "c" ] && (builtins.length ast.definitions) >= 3;
}
