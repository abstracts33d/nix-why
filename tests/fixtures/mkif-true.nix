{ lib }:
{
  modules = [
    {
      options.foo.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "test";
      };
      options.gate = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "test";
      };
    }
    (
      { config, ... }:
      {
        config.foo.enable = lib.mkIf config.gate true;
      }
    )
  ];

  path = "foo.enable";

  # mkIf condition (gate=true) evaluates true; the def contributes.
  # Note: this fixture uses a function module so from-modules.nix
  # (which skips function modules) sees no definitions and we degrade
  # to options-surface. That degradation is the contract: assertions
  # check only that the merge result is consistent.
  assertions = ast: ast.kind == "option" && ast.value == true && ast.winningPriority == 100;
}
