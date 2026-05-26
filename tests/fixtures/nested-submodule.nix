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

  # Submodule option; the path traverses through a submodule boundary.
  assertions = ast: ast.kind == "option" && ast.value == true && ast.type == "bool";
}
