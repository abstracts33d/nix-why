{ lib }:
{
  modules = [
    {
      options.containers = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options.hostname = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "test";
              };
              options.enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "test";
              };
            }
          )
        );
        default = { };
        description = "test";
      };
      config.containers.web.enable = true;
    }
  ];

  path = "containers.web.hostname";

  # The submodule sub-option `hostname` defaults to `name` (the attrsOf
  # key). The pivot must seed `_module.args.name = "web"` into its
  # synthetic evalModules, or forcing the default aborts uncatchably
  # (the submodule function `{ name, ... }:` is called without `name`).
  assertions = ast: ast.kind == "option" && ast.value == "web";
}
