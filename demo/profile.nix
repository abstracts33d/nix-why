# A shared profile, the kind of thing many hosts import.
{ lib, ... }:
{
  # mkDefault: a soft default the host below overrides.
  config.services.webapp.enable = lib.mkDefault true;

  # mkForce here will collide with the host's mkForce on the same option.
  config.services.webapp.port = lib.mkForce 8080;
}
