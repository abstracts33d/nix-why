{ lib }:
{
  modules = [
    {
      options.services.foo.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "test";
      };
      options.services.foo.port = lib.mkOption {
        type = lib.types.int;
        default = 8080;
        description = "test";
      };
      config.services.foo.enable = true;
    }
  ];

  path = "services.foo.enable";

  # Direct nested options under services.foo.* (no submodule wrapper).
  # Companion fixtures: submodule-single, submodule-attrsof,
  # submodule-nested cover the real lib.types.submodule path now that
  # submodule traversal is shipped.
  assertions = ast: ast.kind == "option" && ast.value == true && ast.type == "bool";
}
