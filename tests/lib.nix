{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;
  nixWhy = import ../lib { inherit lib; };

  # Common module disabling _module.check so intentionally-invalid
  # fixtures (type-mismatch, mkforce-collision) can be evaluated lazily
  # without the check pass eagerly walking config and throwing before
  # the library's tryEval-guarded reads.
  permissive = { config._module.check = false; };

  # Run a single fixture through resolve and apply its assertion.
  runFixture =
    name:
    let
      fixture = import (./fixtures + "/${name}.nix") { inherit lib; };
      eval = lib.evalModules { modules = fixture.modules ++ [ permissive ]; };
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
    # v0.1
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
    # v0.2
    "mkforce-collision"
    "type-mismatch"
  ];

  fixtureResults = map runFixture fixtureNames;

  # Diagnostic dump for failed fixtures: include a compact summary of
  # the AST shape so the runCommand error message identifies WHICH
  # field disagreed with the assertion. Only emitted for failures.
  failureDiag =
    r:
    let
      a = r.ast;
    in
    {
      name = r.name;
      kind = a.kind or null;
      value = a.value or null;
      isDefined = a.isDefined or null;
      type = a.type or null;
      winningPriority = a.winningPriority or null;
      definitionsCount = builtins.length (a.definitions or [ ]);
      conflictsCount = builtins.length (a.conflicts or [ ]);
    };

  # v0.3 inline tests for whatSets and search. These don't fit the
  # fixture pattern because they exercise alternate library entry
  # points, not the default resolve path.
  v03Tests =
    let
      simpleModules = [
        { options.foo.enable = lib.mkOption { type = lib.types.bool; default = false; description = "test"; }; }
        { config.foo.enable = true; }
        { config.foo.enable = lib.mkForce false; }
      ];
      simpleEval = lib.evalModules { modules = simpleModules ++ [ permissive ]; };

      searchOptionsModules = [
        { options.services.openssh.enable = lib.mkOption { type = lib.types.bool; default = false; description = "test"; }; }
        { options.services.openssh.port = lib.mkOption { type = lib.types.int; default = 22; description = "test"; }; }
        { options.services.openvpn.enable = lib.mkOption { type = lib.types.bool; default = false; description = "test"; }; }
      ];
      searchEval = lib.evalModules { modules = searchOptionsModules ++ [ permissive ]; };
    in
    [
      {
        name = "whatSets-finds-setters";
        passed =
          let
            ast = nixWhy.whatSets {
              modules = simpleModules;
              config = simpleEval.config;
              options = simpleEval.options;
              path = "foo.enable";
            };
          in
          ast.kind == "option" && (builtins.length ast.setters) >= 1 && (builtins.length ast.declarations) >= 1;
      }
      {
        name = "search-infix-match";
        passed =
          let
            r = nixWhy.search {
              options = searchEval.options;
              pattern = "openssh";
              limit = 50;
            };
          in
          r.totalMatches == 2 && (lib.all (m: lib.hasInfix "openssh" m.path) r.matches);
      }
      {
        name = "search-empty-pattern-matches-everything";
        passed =
          let
            r = nixWhy.search {
              options = searchEval.options;
              pattern = "";
              limit = 50;
            };
          in
          r.totalMatches >= 3;
      }
      {
        name = "search-respects-limit-and-truncated-flag";
        passed =
          let
            r = nixWhy.search {
              options = searchEval.options;
              pattern = "services";
              limit = 2;
            };
          in
          (builtins.length r.matches) == 2 && r.totalMatches == 3 && r.truncated == true;
      }
      {
        name = "search-no-match-returns-empty";
        passed =
          let
            r = nixWhy.search {
              options = searchEval.options;
              pattern = "nonexistent-substring";
              limit = 50;
            };
          in
          r.totalMatches == 0 && r.truncated == false;
      }
    ];

  v03Results = map (t: {
    name = t.name;
    passed = t.passed;
  }) v03Tests;

  results = fixtureResults ++ v03Results;
  failures = builtins.filter (r: !r.passed) results;
  fixtureFailures = builtins.filter (r: !r.passed) fixtureResults;
in
{
  inherit results failures;
  failureDiagnostics = map failureDiag fixtureFailures;
  pass = failures == [ ];
  summary = "${toString (builtins.length results)} tests (${toString (builtins.length fixtureResults)} fixtures + ${toString (builtins.length v03Results)} v0.3 inline), ${toString (builtins.length failures)} failed";
}
