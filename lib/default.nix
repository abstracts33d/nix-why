{ lib }:
let
  internal =
    (import ./internal/priority.nix { inherit lib; })
    // (import ./internal/walker.nix { inherit lib; })
    // (import ./internal/from-options.nix { inherit lib; })
    // (import ./internal/from-modules.nix { inherit lib; })
    // (import ./internal/nix-source.nix { inherit lib; });

  whyOption = import ./why-option.nix { inherit lib internal; };

  adapters = import ./adapters/default.nix { inherit lib; };
in
{
  inherit (whyOption)
    resolve
    render
    whatSets
    search
    ;
  inherit adapters;
}
