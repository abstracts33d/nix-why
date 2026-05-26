{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;
  nixWhy = import ../lib { inherit lib; };

  # Run a single fixture through resolve and apply its assertion.
  runFixture =
    name:
    let
      fixture = import (./fixtures + "/${name}.nix") { inherit lib; };
      eval = lib.evalModules { modules = fixture.modules; };
      ast = nixWhy.resolve {
        modules = fixture.modules;
        config = eval.config;
        options = eval.options;
        path = fixture.path;
      };
      passed = fixture.assertions ast;
    in
    {
      inherit name passed ast;
    };

  fixtureNames = [
    "basic-bool"
    "mkdefault-chain"
    "mkforce-overrides"
    "mkif-true"
    "mkif-false"
    "mkmerge"
    "list-merge"
    "nested-submodule"
    "declared-not-defined"
    "nonexistent-option"
    "dup-in-file"
    "custom-priority"
    "freeform"
  ];

  results = map runFixture fixtureNames;
  failures = builtins.filter (r: !r.passed) results;
in
{
  inherit results failures;
  pass = failures == [ ];
  summary = "${toString (builtins.length results)} fixtures, ${toString (builtins.length failures)} failed";
}
