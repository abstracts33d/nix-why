{ lib }:
{
  modules = [
    {
      options.foo.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "test";
      };
    }
  ];

  path = "foo.enable";

  # Option declared with a default, never set by user config. NixOS
  # represents the default itself as a definition at priority 1500
  # (mkOptionDefault), so:
  #   isDefined        = true   (the default counts)
  #   winningPriority  = 1500
  #   value            = false  (the declared default)
  #
  # A future "is this *explicitly* set" view (v0.4 territory) would
  # filter on priority != 1500 to distinguish user-supplied
  # definitions from the type default.
  assertions =
    ast:
    ast.kind == "option" && ast.value == false && ast.winningPriority == 1500;
}
