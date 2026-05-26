{ lib }:
{
  modules = [
    {
      _module.freeformType = lib.types.attrsOf lib.types.str;
      config.someFreeAttr = "free-value";
    }
  ];

  path = "someFreeAttr";

  # Freeform attrs are not declared as options, so the option tree does
  # not contain them. The library should return kind="not-found" rather
  # than crashing on the freeform machinery.
  assertions = ast: ast.kind == "not-found";
}
