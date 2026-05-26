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
    in
    {
      # The strategic asset: pure Nix introspection library. System-
      # agnostic; consumers do:
      #   inputs.nix-why.lib.resolve { options, modules, path, ... }
      lib = import ./lib { inherit (nixpkgs) lib; };

      formatter = eachSystem (system: treefmtEval.${system}.config.build.wrapper);

      checks = eachSystem (system: {
        treefmt = treefmtEval.${system}.config.build.check self;
      });

      devShells = eachSystem (system: {
        default = (pkgsFor system).mkShellNoCC {
          packages = with pkgsFor system; [
            bats
            shellcheck
            shfmt
            nixfmt-rfc-style
            statix
            deadnix
            jq
          ];
        };
      });
    };
}
