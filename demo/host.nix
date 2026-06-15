# The host configuration.
{ lib, config, ... }:
{
  # Plain definition (priority 100) wins over the profile's mkDefault (1000).
  config.services.webapp.enable = true;

  # A second mkForce on the same option as the profile -> merge conflict.
  config.services.webapp.port = lib.mkForce 9090;

  # Cluster mode is off, so the mkIf below never fires and `workers` keeps
  # its default. `why-not` surfaces this gated definition.
  config.services.webapp.cluster.enable = false;
  config.services.webapp.workers = lib.mkIf config.services.webapp.cluster.enable 8;
}
