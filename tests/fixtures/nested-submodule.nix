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

  # Nested options under services.foo.*. NB: this is direct nesting via
  # the dotted-attribute syntax, not a `lib.types.submodule` wrapper.
  # Real submodule types expose their sub-options through
  # `option.type.getSubOptions`, not as siblings on the parent option,
  # so direct path traversal into `options.services.foo.<sub>` would
  # not find them. Walking into a submodule is a planned v0.2+
  # enhancement; v0.1 covers direct nesting only.
  assertions = ast: ast.kind == "option" && ast.value == true && ast.type == "bool";
}
