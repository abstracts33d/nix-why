{ lib }:
{
  modules = [
    {
      options.x.a = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "test";
      };
    }
    # Outer mkForce (priority 50) wrapping an attrset whose leaf carries
    # an inner mkDefault (priority 1000). nixpkgs pushes the outer
    # override down onto nested attrs, so the leaf's effective priority is
    # the OUTERMOST wrapper (50), not the innermost (1000). Pre-fix the
    # walker accumulated the innermost priority and mismarked the winner.
    { config.x = lib.mkForce { a = lib.mkDefault 1; }; }
    { config.x.a = lib.mkDefault 9; }
  ];

  path = "x.a";

  # The merged value of this degenerate nested-override form errors in
  # nixpkgs itself, so we assert on the module-walk's priority
  # attribution rather than on ast.value: the mkForce-originated leaf must
  # carry the outermost priority (50) and be the winner.
  assertions = ast: builtins.any (d: d.priority == 50 && d.value == 1 && d.wins) ast.definitions;
}
