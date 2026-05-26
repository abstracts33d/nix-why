{ lib }:
let
  # Priority numbers come from nixpkgs lib/modules.nix. Lower numbers win
  # the merge. The "default" label corresponds to a value with no
  # priority wrapper (i.e. plain `option = value`), which evaluates with
  # priority 100.
  named = {
    "10" = "mkVMOverride";
    "50" = "mkForce";
    "60" = "mkImageMediaOverride";
    "100" = "default";
    "1000" = "mkDefault";
    "1500" = "mkOptionDefault";
  };
in
{
  # labelFor :: int -> string
  #
  # Returns the human-readable label for a numeric priority. Unnamed
  # priorities are rendered as "mkOverride <N>".
  labelFor =
    priority:
    let
      key = toString priority;
    in
    named.${key} or "mkOverride ${toString priority}";

  # isNamed :: int -> bool
  #
  # True iff the priority matches a well-known NixOS module-system level.
  isNamed = priority: named ? ${toString priority};
}
