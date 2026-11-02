# Non-flake entry point for vanilla-nix consumers. Mirrors the flake
# outputs without referencing flakes:
#
#   nix-build -A nix-why-option
#   (import ./. { }).lib.resolve { ... }
#
# `pkgs` defaults to <nixpkgs> but can be passed explicitly to pin it.
{
  pkgs ? import <nixpkgs> { },
}:
let
  packages = pkgs.callPackage ./package.nix { };
in
{
  # Pure-Nix introspection library. System-agnostic; takes only `lib`.
  lib = import ./lib { inherit (pkgs) lib; };

  inherit (packages)
    nix-why-option
    nix-why-conflict
    nix-why-recursion
    nix-why-overlay
    ;

  # `default` so `nix-build` with no -A yields the flagship.
  default = packages.nix-why-option;

  # Consumer overlay: adds the four CLIs to a nixpkgs instance. Keys are
  # listed literally so the overlay's shape is known without forcing
  # `final` (returning the callPackage result directly recurses via
  # callPackage's intersectAttrs).
  overlays.default = final: _prev: {
    inherit (final.callPackage ./package.nix { })
      nix-why-option
      nix-why-conflict
      nix-why-recursion
      nix-why-overlay
      ;
  };
}
