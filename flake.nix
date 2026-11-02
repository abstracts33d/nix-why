{
  description = "Diagnostic tools for Nix evaluations: why is this NixOS / home-manager / nix-darwin option set to this value?";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      treefmt-nix,
    }:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      treefmtEval = eachSystem (system: treefmt-nix.lib.evalModule (pkgsFor system) ./treefmt.nix);

      # The CLI derivations live in package.nix so the flake and the
      # non-flake default.nix build them the same way. callPackage feeds
      # in stdenv/makeWrapper/jq/nix/coreutils; version comes from
      # version.nix.
      packagesFor = system: (pkgsFor system).callPackage ./package.nix { };
    in
    {
      # The strategic asset: pure Nix introspection library. System-
      # agnostic; consumers do:
      #   inputs.nix-why.lib.resolve { options, modules, path, ... }
      lib = import ./lib { inherit (nixpkgs) lib; };

      # Consumer-facing overlay: adds the four CLIs to a nixpkgs instance so
      # downstream flakes (fleet dev hosts) get `pkgs.nix-why-option` etc.
      # without referencing per-system `packages`. Built from `final` so the
      # CLIs resolve deps through the consumer's package set.
      # Output keys are listed literally so the overlay's attrset shape is
      # known without forcing `final` - returning the callPackage result
      # directly makes the keyset depend on `final`'s keyset (infinite
      # recursion via callPackage's intersectAttrs).
      overlays.default = final: _prev: {
        inherit (final.callPackage ./package.nix { })
          nix-why-option
          nix-why-conflict
          nix-why-recursion
          nix-why-overlay
          ;
      };

      # Inherit the four explicitly: callPackage wraps its result in
      # makeOverridable, so `p` also carries override/overrideDerivation,
      # which are not derivations and break `nix flake check` if exposed.
      packages = eachSystem (
        system:
        let
          p = packagesFor system;
        in
        {
          inherit (p)
            nix-why-option
            nix-why-conflict
            nix-why-recursion
            nix-why-overlay
            ;
          default = p.nix-why-option;
        }
      );

      apps = eachSystem (system: {
        option = {
          type = "app";
          program = "${self.packages.${system}.nix-why-option}/bin/nix-why-option";
          meta = {
            description = "Module-system option resolution debugger";
            mainProgram = "nix-why-option";
          };
        };
        conflict = {
          type = "app";
          program = "${self.packages.${system}.nix-why-conflict}/bin/nix-why-conflict";
          meta = {
            description = "Focused view on merge conflicts for a single option";
            mainProgram = "nix-why-conflict";
          };
        };
        recursion = {
          type = "app";
          program = "${self.packages.${system}.nix-why-recursion}/bin/nix-why-recursion";
          meta = {
            description = "Surface infinite-recursion cycles in --show-trace output";
            mainProgram = "nix-why-recursion";
          };
        };
        overlay = {
          type = "app";
          program = "${self.packages.${system}.nix-why-overlay}/bin/nix-why-overlay";
          meta = {
            description = "List nixpkgs overlays applied to a flake target";
            mainProgram = "nix-why-overlay";
          };
        };
        default = self.apps.${system}.option;
      });

      formatter = eachSystem (system: treefmtEval.${system}.config.build.wrapper);

      checks = eachSystem (
        system:
        let
          pkgs = pkgsFor system;
          libResult = import ./tests/lib.nix { inherit pkgs; };
        in
        {
          treefmt = treefmtEval.${system}.config.build.check self;

          # Pure-Nix unit tests via lib.runTests. The library evaluation
          # happens at flake-eval time; the runCommand below is a tiny
          # success marker, no IFD beyond the toJSON failure report.
          lib-tests =
            if libResult.pass then
              pkgs.runCommand "nix-why-lib-tests" { } ''
                echo "${libResult.summary}"
                touch $out
              ''
            else
              throw "nix-why: lib tests failed (${libResult.summary}): ${
                builtins.toJSON (map (r: r.name) libResult.failures)
              }";

          # CLI-surface bats tests; no Nix evaluation required at test
          # runtime (all tests cover argv / help / error paths that do
          # not invoke `nix eval`).
          #
          # We copy the whole flake source into the build dir so the
          # bats test files can resolve REPO_ROOT relative to themselves
          # (they need cli/nix-why-* and lib/ to be adjacent).
          cli-tests =
            pkgs.runCommand "nix-why-cli-tests"
              {
                buildInputs = [
                  pkgs.bats
                  pkgs.jq
                  pkgs.bash
                  pkgs.coreutils
                ];
              }
              ''
                cp -r ${./.} ./repo
                chmod -R u+w ./repo
                cd ./repo

                # /usr/bin/env does not exist in the Nix sandbox, so
                # the scripts' `#!/usr/bin/env bash` shebangs fail with
                # "bad interpreter". patchShebangs (from stdenv) rewrites
                # them to the absolute store path of bash. Packaged
                # binaries get this automatically via wrapProgram; the
                # raw-source-copy form in this runCommand needs it
                # applied explicitly.
                chmod +x cli/nix-why-option cli/nix-why-conflict \
                         cli/nix-why-recursion cli/nix-why-overlay
                patchShebangs cli/nix-why-option cli/nix-why-conflict \
                              cli/nix-why-recursion cli/nix-why-overlay

                # The CLIs read NIX_WHY_LIB, NIX_WHY_CLI_EXPR_DIR and
                # NIX_WHY_CLI_SH to locate the Nix library, the .nix
                # driver expressions and the shared bash helpers.
                # Bats tests cover argv / help / error paths that do
                # not actually run `nix eval`, so the values do not
                # need to point at valid trees - just set them so the
                # startup validation does not trip.
                export NIX_WHY_LIB="$PWD/lib"
                export NIX_WHY_CLI_EXPR_DIR="$PWD/cli/expr"
                export NIX_WHY_CLI_SH="$PWD/cli/_lib.sh"

                ${pkgs.bats}/bin/bats tests/cli.bats tests/siblings.bats
                touch $out
              '';
        }
      );

      devShells = eachSystem (system: {
        default = (pkgsFor system).mkShellNoCC {
          packages = with pkgsFor system; [
            bats
            shellcheck
            shfmt
            nixfmt
            statix
            deadnix
            jq
          ];
          shellHook = ''
            export NIX_WHY_LIB="$PWD/lib"
            echo "nix-why dev shell. NIX_WHY_LIB=$NIX_WHY_LIB"
          '';
        };
      });
    };
}
