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

      mkNixWhyOption =
        pkgs:
        pkgs.stdenv.mkDerivation {
          pname = "nix-why-option";
          version = "0.1.0-pre";
          src = ./.;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          dontConfigure = true;
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin $out/share/nix-why
            cp -r lib $out/share/nix-why/lib
            install -Dm755 cli/nix-why-option $out/bin/nix-why-option
            wrapProgram $out/bin/nix-why-option \
              --set NIX_WHY_LIB $out/share/nix-why/lib \
              --prefix PATH : ${
                nixpkgs.lib.makeBinPath [
                  pkgs.jq
                  pkgs.nix
                ]
              }
            runHook postInstall
          '';
          meta = {
            description = "Module-system option resolution debugger";
            mainProgram = "nix-why-option";
            license = nixpkgs.lib.licenses.mit;
            platforms = nixpkgs.lib.platforms.unix;
          };
        };
    in
    {
      # The strategic asset: pure Nix introspection library. System-
      # agnostic; consumers do:
      #   inputs.nix-why.lib.resolve { options, modules, path, ... }
      lib = import ./lib { inherit (nixpkgs) lib; };

      packages = eachSystem (system: rec {
        nix-why-option = mkNixWhyOption (pkgsFor system);
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
              }\nFixture diagnostics: ${builtins.toJSON libResult.failureDiagnostics}";

          # CLI-surface bats tests; no Nix evaluation required at test
          # runtime (all tests in cli.bats cover argv / help / error
          # paths that do not invoke `nix eval`).
          #
          # We copy the whole flake source into the build dir so the
          # bats test file can resolve REPO_ROOT relative to itself
          # (it needs cli/nix-why-option and lib/ to be adjacent).
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

                # Make sure the CLI script is executable - cp from
                # /nix/store sometimes drops mode bits depending on the
                # source tree origin.
                chmod +x cli/nix-why-option

                # Diagnostic: surface the state of the script + lib
                # before bats runs, so any failure points at the real
                # cause.
                echo "=== diagnostics ==="
                pwd
                ls -la cli/nix-why-option
                head -1 cli/nix-why-option
                ls -la lib/default.nix
                echo "PATH=$PATH"
                echo "=== run cli --help directly ==="
                ./cli/nix-why-option --help || echo "(direct --help exit: $?)"
                echo "=== bats ==="
                ${pkgs.bats}/bin/bats tests/cli.bats
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
