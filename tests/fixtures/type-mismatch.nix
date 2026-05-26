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
    { config.foo.bar = 42; }
  ];

  path = "foo.bar";

  # bool option set to an int: the type check throws when the merge
  # tries to validate. valueError is populated; conflicts[] gets a
  # merge-conflict entry. The walker still sees the assignment (42 is
  # the raw value at priority 100), so definitions list is non-empty.
  assertions = ast: ast.kind == "option" && ast.value == null && ast.valueError != null;
}
