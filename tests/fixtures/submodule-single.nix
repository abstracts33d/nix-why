{ lib }:
{
  modules = [
    {
      options.services.foo = lib.mkOption {
        type = lib.types.submodule {
          options.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "test";
          };
          options.port = lib.mkOption {
            type = lib.types.int;
            default = 8080;
            description = "test";
          };
        };
        default = { };
        description = "test";
      };
      config.services.foo.enable = true;
    }
  ];

  path = "services.foo.enable";

  # Single-instance submodule pivot: `services.foo` is declared with
  # lib.types.submodule, so reaching `services.foo.enable` requires
  # pivoting through the submodule's own evalModules. The library
  # should re-evaluate the submodule with the user's config.foo.enable
  # extracted as a synthetic module, then resolve `.enable` in the
  # resulting options tree.
  assertions = ast: ast.kind == "option" && ast.value == true && ast.type == "bool";
}
