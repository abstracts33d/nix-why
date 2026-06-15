{ lib }:
{
  modules = [
    {
      options.myset = lib.mkOption {
        type = lib.types.submodule {
          freeformType = lib.types.attrsOf lib.types.anything;
          options.declared = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "test";
          };
        };
        default = { };
        description = "test";
      };
    }
    # `undeclared` is set via the freeform type - it has a value in config
    # but is NOT a declared option. nixos-option surfaces such values; the
    # tool must too (kind = "freeform") rather than claiming the path does
    # not exist. This is the nix.settings.experimental-features case.
    { config.myset.undeclared = "hello"; }
  ];

  path = "myset.undeclared";

  assertions = ast: ast.kind == "freeform" && ast.value == "hello" && ast.isDefined == true;
}
