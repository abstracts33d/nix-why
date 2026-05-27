# Configuration that intentionally creates an unresolvable merge
# conflict on services.test.enable for the nix-why-conflict test.
# Two mkForce wrappers on the same option at the same priority with
# different values triggers the conflicts[] block.
{ lib, ... }:
{
  config = lib.mkMerge [
    { services.test.enable = lib.mkForce true; }
    { services.test.enable = lib.mkForce false; }
  ];
}
