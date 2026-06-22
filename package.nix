# CLI package definitions, shared by flake.nix and the non-flake
# default.nix so there is a single source of truth for how the tools are
# built. callPackage-shaped: `pkgs.callPackage ./package.nix { }` yields
# the four CLI derivations.
{
  lib,
  stdenv,
  makeWrapper,
  jq,
  nix,
  coreutils,
  version ? import ./version.nix,
}:
let
  # Path literal, not a callPackage arg: a `src` formal would collide with
  # nixpkgs' renamed-package `src` throw and be injected by callPackage.
  src = ./.;

  # Each cli script shares the same shape:
  #   - wrap with NIX_WHY_LIB set to the shared lib copy (when needsLib)
  #   - wrap with NIX_WHY_CLI_EXPR_DIR set to the cli/expr/ copy (when
  #     needsExpr) - the CLI calls `nix eval -f` on these instead of
  #     building heredoc-Nix at runtime
  #   - jq + nix + coreutils in PATH
  mkCliScript =
    {
      name,
      desc,
      needsLib ? true,
      needsExpr ? true,
      extraDeps ? [ ],
    }:
    stdenv.mkDerivation {
      pname = name;
      inherit version src;
      nativeBuildInputs = [ makeWrapper ];
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin $out/share/nix-why
        ${lib.optionalString needsLib "cp -r lib $out/share/nix-why/lib"}
        ${lib.optionalString needsExpr "cp -r cli/expr $out/share/nix-why/cli-expr"}
        install -Dm644 cli/_lib.sh $out/share/nix-why/_lib.sh
        install -Dm755 cli/${name} $out/bin/${name}
        wrapProgram $out/bin/${name} \
          --set NIX_WHY_VERSION ${version} \
          --set NIX_WHY_CLI_SH $out/share/nix-why/_lib.sh \
          ${lib.optionalString needsLib "--set NIX_WHY_LIB $out/share/nix-why/lib"} \
          ${lib.optionalString needsExpr "--set NIX_WHY_CLI_EXPR_DIR $out/share/nix-why/cli-expr"} \
          --prefix PATH : ${
            lib.makeBinPath (
              [
                jq
                nix
                # GNU coreutils pinned so mktemp/realpath/sort behave
                # identically on darwin (BSD userland) and linux.
                coreutils
              ]
              ++ extraDeps
            )
          }
        runHook postInstall
      '';
      meta = {
        description = desc;
        mainProgram = name;
        license = lib.licenses.mit;
        platforms = lib.platforms.unix;
      };
    };
in
{
  nix-why-option = mkCliScript {
    name = "nix-why-option";
    desc = "Module-system option resolution debugger";
  };
  nix-why-conflict = mkCliScript {
    name = "nix-why-conflict";
    desc = "Focused view on merge conflicts for a single option";
  };
  nix-why-recursion = mkCliScript {
    name = "nix-why-recursion";
    desc = "Surface infinite-recursion cycles in --show-trace output";
    # The recursion tool is a pure text parser; no library or Nix
    # expressions needed.
    needsLib = false;
    needsExpr = false;
  };
  nix-why-overlay = mkCliScript {
    name = "nix-why-overlay";
    desc = "List nixpkgs overlays applied to a flake target";
    # Overlay tool uses its own Nix expressions, no nix-why library
    # involvement.
    needsLib = false;
  };
}
