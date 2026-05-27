{ lib }:
{
  modules = [
    {
      options.services.outer = lib.mkOption {
        type = lib.types.submodule {
          options.inner = lib.mkOption {
            type = lib.types.submodule {
              options.enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "test";
              };
            };
            default = { };
            description = "test";
          };
        };
        default = { };
        description = "test";
      };
      config.services.outer.inner.enable = true;
    }
  ];

  path = "services.outer.inner.enable";

  # Submodule inside submodule: the path crosses TWO submodule
  # boundaries. The pivot machinery recurses naturally - after the
  # first pivot lands in `services.outer`'s evaluated sub-options
  # tree, walkOptions encounters `inner` (a submodule-typed option)
  # and pivots again. The second pivot only has the synthetic modules
  # from the first pivot's evalModules result to work with, so deep
  # nested cases retain less per-module attribution - but the value
  # and type resolve correctly.
  assertions = ast: ast.kind == "option" && ast.value == true && ast.type == "bool";
}
