_: {
  projectRootFile = "flake.nix";

  programs = {
    nixfmt.enable = true;
    deadnix.enable = true;
    statix.enable = true;
    shfmt.enable = true;
    shellcheck.enable = true;
  };

  settings = {
    formatter.shfmt.options = [
      "--indent"
      "2"
      "--case-indent"
      "--space-redirects"
    ];
  };
}
