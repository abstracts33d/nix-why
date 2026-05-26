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
  ];

  path = "foo.enable";

  # Option declared but never set by any module. isDefined is false, but
  # `value` still returns the declared default (the library is permissive
  # here for ergonomics).
  assertions =
    ast:
    ast.kind == "option" && ast.isDefined == false && (builtins.length ast.definitions) == 0;
}
