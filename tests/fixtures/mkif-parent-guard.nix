{ lib }:
{
  modules = [
    {
      options.services.foo.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "test";
      };
    }
    {
      # mkIf guards the PARENT attrset, not the leaf. The leaf (`enable`)
      # sits on a later line than the `mkIf`. Pre-fix the guard-source
      # extractor scanned forward from the leaf position and missed the
      # mkIf (it is above the leaf); post-fix it scans from the condition's
      # own recorded position and recovers the text.
      config.services.foo = lib.mkIf true {
        enable = true;
      };
    }
  ];

  path = "services.foo.enable";

  assertions =
    ast:
    ast.kind == "option"
    && ast.value == true
    && builtins.any (d: d.guardedBy != null && d.guardedBy.source == "true") ast.definitions;
}
