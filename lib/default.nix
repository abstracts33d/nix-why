/**
  Public entry point for the nix-why library.

  Pure-Nix introspection of the NixOS module system. Given an
  evaluated NixOS / home-manager / nix-darwin / flake-parts /
  raw-evalModules configuration, answers four questions about a
  single option path:

  - `resolve`   — what is the final value, where does it come from,
                  what are the contributing definitions?
  - `whatSets`  — which modules carry a definition for this option,
                  including those that lost the merge or were
                  filtered out by an `mkIf`?
  - `whyNot`    — why is this option not explicitly set (and what
                  would set it if conditions changed)?
  - `search`    — fuzzy-match an option path against the options
                  tree, descending into submodules.

  Adapters that map a flake's evaluated configuration shape onto
  this library's `{ modules, config, options }` contract live under
  `adapters/`.

  # Stability

  The four public functions (`resolve`, `whatSets`, `whyNot`,
  `search`) and the adapter facade (`adapters.adapt`,
  `adapters.byName`) are part of the stable API. Anything under
  `lib/internal/` is implementation detail and may change without
  notice.

  # Example

  ```nix
  let
    flake = builtins.getFlake (toString ./.);
    cfg = flake.nixosConfigurations.myhost;
    nixWhy = import (builtins.fetchTree { … }) { inherit (pkgs) lib; };
    adapted = nixWhy.adapters.adapt { flakeOutput = cfg; };
  in
    nixWhy.resolve {
      inherit (adapted) modules config options;
      path = "services.openssh.enable";
    }
  ```
*/
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
    whatSets
    search
    whyNot
    ;
  inherit adapters;
}
