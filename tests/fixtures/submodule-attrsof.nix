{ lib }:
{
  modules = [
    {
      options.services.foo = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
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
          }
        );
        default = { };
        description = "test";
      };
      config.services.foo.web.enable = true;
      config.services.foo.api.port = 9090;
    }
  ];

  path = "services.foo.web.enable";

  # attrsOf submodule: `services.foo` is declared with attrsOf
  # (submodule {...}), so reaching `services.foo.web.enable` requires
  # consuming "web" as the user-supplied attrsOf key, then pivoting
  # into the submodule for "enable". The library extracts each user
  # module's config at `services.foo.web`, feeds it into a fresh
  # lib.evalModules of the inner submodule, and resolves `.enable`
  # in the result.
  assertions = ast: ast.kind == "option" && ast.value == true && ast.type == "bool";
}
