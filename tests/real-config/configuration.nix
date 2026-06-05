# Minimal but REAL NixOS configuration: a full lib.nixosSystem eval
# (the entire NixOS module set, deep imports, function modules needing
# pkgs/modulesPath/specialArgs) - the shape that the flat evalModules
# synthetic fixture deliberately does not cover, and the shape that
# previously made nix-why hard-crash. See tests/smoke/real-config.sh.
{ lib, ... }:
{
  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  # A non-trivial winner: mkDefault so resolve reports priority 1000.
  services.openssh.enable = lib.mkDefault true;
  system.stateVersion = "24.11";
}
