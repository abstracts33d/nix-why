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
      # Single source of truth for the package version. Bump this when
      # cutting a release; both the derivation version and the runtime
      # --version output read from here.
      nixWhyVersion = "0.5.1";

      eachSystem = nixpkgs.lib.genAttrs (import systems);
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      treefmtEval = eachSystem (system: treefmt-nix.lib.evalModule (pkgsFor system) ./treefmt.nix);

      # Helper: package one of the cli scripts. All siblings share the
      # same shape:
      #   - wrap with NIX_WHY_LIB set to the shared lib copy (when
      #     needsLib)
      #   - wrap with NIX_WHY_CLI_EXPR_DIR set to the cli/expr/ copy
      #     (when needsExpr) - the CLI calls `nix eval -f` on these
      #     instead of building heredoc-Nix at runtime
      #   - jq + nix in PATH
      mkCliScript =
        {
          name,
          desc,
          needsLib ? true,
          needsExpr ? true,
          extraDeps ? [ ],
        }:
        pkgs:
        pkgs.stdenv.mkDerivation {
          pname = name;
          version = nixWhyVersion;
          src = ./.;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          dontConfigure = true;
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin $out/share/nix-why
            ${nixpkgs.lib.optionalString needsLib "cp -r lib $out/share/nix-why/lib"}
            ${nixpkgs.lib.optionalString needsExpr "cp -r cli/expr $out/share/nix-why/cli-expr"}
            install -Dm644 cli/_lib.sh $out/share/nix-why/_lib.sh
            install -Dm755 cli/${name} $out/bin/${name}
            wrapProgram $out/bin/${name} \
              --set NIX_WHY_VERSION ${nixWhyVersion} \
              --set NIX_WHY_CLI_SH $out/share/nix-why/_lib.sh \
              ${nixpkgs.lib.optionalString needsLib "--set NIX_WHY_LIB $out/share/nix-why/lib"} \
              ${nixpkgs.lib.optionalString needsExpr "--set NIX_WHY_CLI_EXPR_DIR $out/share/nix-why/cli-expr"} \
              --prefix PATH : ${
                nixpkgs.lib.makeBinPath (
                  [
                    pkgs.jq
                    pkgs.nix
                    # GNU coreutils pinned so mktemp/realpath/sort behave
                    # identically on darwin (BSD userland) and linux.
                    pkgs.coreutils
                  ]
                  ++ extraDeps
                )
              }
            runHook postInstall
          '';
          meta = {
            description = desc;
            mainProgram = name;
            license = nixpkgs.lib.licenses.mit;
            platforms = nixpkgs.lib.platforms.unix;
          };
        };

      mkNixWhyOption = mkCliScript {
        name = "nix-why-option";
        desc = "Module-system option resolution debugger";
      };
      mkNixWhyConflict = mkCliScript {
        name = "nix-why-conflict";
        desc = "Focused view on merge conflicts for a single option";
      };
      mkNixWhyRecursion = mkCliScript {
        name = "nix-why-recursion";
        desc = "Surface infinite-recursion cycles in --show-trace output";
        # The recursion tool is a pure text parser; no library or Nix
        # expressions needed.
        needsLib = false;
        needsExpr = false;
      };
      mkNixWhyOverlay = mkCliScript {
        name = "nix-why-overlay";
        desc = "List nixpkgs overlays applied to a flake target";
        # Overlay tool uses its own Nix expressions, no nix-why library
        # involvement.
        needsLib = false;
      };
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
      overlays.default = final: _prev: {
        nix-why-option = mkNixWhyOption final;
        nix-why-conflict = mkNixWhyConflict final;
        nix-why-recursion = mkNixWhyRecursion final;
        nix-why-overlay = mkNixWhyOverlay final;
      };

      packages = eachSystem (system: rec {
        nix-why-option = mkNixWhyOption (pkgsFor system);
        nix-why-conflict = mkNixWhyConflict (pkgsFor system);
        nix-why-recursion = mkNixWhyRecursion (pkgsFor system);
        nix-why-overlay = mkNixWhyOverlay (pkgsFor system);
        default = nix-why-option;
      });

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
