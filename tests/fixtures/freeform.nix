{ lib }:
{
  modules = [
    {
      freeformType = lib.types.attrsOf lib.types.str;
      config.someFreeAttr = "free-value";
    }
  ];

  path = "someFreeAttr";

  # Freeform attrs are not declared as options, so the option tree does
  # not contain them. The library should return kind="not-found" rather
  # than crashing on the freeform machinery.
  #
  # Note: `freeformType` is a top-level module key (recognised by
  # lib.modules.unifyModuleSyntax alongside config / options / imports).
  # Writing `_module.freeformType` would be rejected when `config` is
  # also at top-level.
  assertions = ast: ast.kind == "not-found";
}
