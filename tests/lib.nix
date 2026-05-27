{
  pkgs ? import <nixpkgs> { },
}:
let
  inherit (pkgs) lib;
  nixWhy = import ../lib { inherit lib; };

  # Common module disabling _module.check so intentionally-invalid
  # fixtures (type-mismatch, mkforce-collision) can be evaluated lazily
  # without the check pass eagerly walking config and throwing before
  # the library's tryEval-guarded reads.
  permissive = {
    config._module.check = false;
  };

  # Run a single fixture through resolve and apply its assertion.
  runFixture =
    name:
    let
      fixture = import (./fixtures + "/${name}.nix") { inherit lib; };
      eval = lib.evalModules { modules = fixture.modules ++ [ permissive ]; };
      ast = nixWhy.resolve {
        inherit (fixture) modules;
        inherit (eval) options config;
        inherit (fixture) path;
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
    # post-v0.5 function-module application
    "function-module"
    # post-v0.5 submodule traversal
    "submodule-single"
    "submodule-attrsof"
    "submodule-nested"
  ];

  fixtureResults = map runFixture fixtureNames;

  # v0.3 inline tests for whatSets and search. These don't fit the
  # fixture pattern because they exercise alternate library entry
  # points, not the default resolve path.
  v03Tests =
    let
      simpleModules = [
        {
          options.foo.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "test";
          };
        }
        { config.foo.enable = true; }
        { config.foo.enable = lib.mkForce false; }
      ];
      simpleEval = lib.evalModules { modules = simpleModules ++ [ permissive ]; };

      searchOptionsModules = [
        {
          options.services.openssh.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "test";
          };
        }
        {
          options.services.openssh.port = lib.mkOption {
            type = lib.types.int;
            default = 22;
            description = "test";
          };
        }
        {
          options.services.openvpn.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "test";
          };
        }
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
              inherit (simpleEval) options config;
              path = "foo.enable";
            };
          in
          ast.kind == "option"
          && (builtins.length ast.setters) >= 1
          && (builtins.length ast.declarations) >= 1;
      }
      {
        name = "search-infix-match";
        passed =
          let
            r = nixWhy.search {
              inherit (searchEval) options;
              pattern = "openssh";
              limit = 50;
            };
            # search doesn't need config; the inherit doesn't matter
          in
          r.totalMatches == 2 && (lib.all (m: lib.hasInfix "openssh" m.path) r.matches);
      }
      {
        name = "search-empty-pattern-matches-everything";
        passed =
          let
            r = nixWhy.search {
              inherit (searchEval) options;
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
              inherit (searchEval) options;
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
              inherit (searchEval) options;
              pattern = "nonexistent-substring";
              limit = 50;
            };
          in
          r.totalMatches == 0 && r.truncated == false;
      }
    ];

  v03Results = map (t: {
    inherit (t) name;
    inherit (t) passed;
  }) v03Tests;

  # v0.4 inline tests for whyNot. The fixture pattern would force every
  # case through `resolve`, so we exercise whyNot directly here.
  v04Tests =
    let
      # Option declared with a user-supplied value. whyNot should report
      # isExplicitlySet = true and a non-empty explicitDefinitions list.
      explicitModules = [
        {
          options.foo.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "test";
          };
        }
        { config.foo.enable = true; }
      ];
      explicitEval = lib.evalModules { modules = explicitModules ++ [ permissive ]; };

      # Option declared with a default and no user config at all.
      # whyNot should report isExplicitlySet = false, exactly one entry
      # in defaultDefinitions (the option's default at priority 1500),
      # and an empty filteredOutDefinitions.
      defaultOnlyModules = [
        {
          options.foo.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "test";
          };
        }
      ];
      defaultOnlyEval = lib.evalModules { modules = defaultOnlyModules ++ [ permissive ]; };

      # Option whose only user-supplied definition is gated by a mkIf
      # that evaluates to false. whyNot should pick up the gated
      # definition in filteredOutDefinitions and emit a non-null hint.
      gatedModules = [
        {
          options.foo.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "test";
          };
        }
        {
          config.foo.enable = lib.mkIf false true;
        }
      ];
      gatedEval = lib.evalModules { modules = gatedModules ++ [ permissive ]; };
    in
    [
      {
        name = "whyNot-explicitly-set";
        passed =
          let
            r = nixWhy.whyNot {
              modules = explicitModules;
              inherit (explicitEval) options;
              path = "foo.enable";
            };
          in
          r.isExplicitlySet == true && (builtins.length r.explicitDefinitions) >= 1 && r.hint == null;
      }
      {
        name = "whyNot-default-only";
        passed =
          let
            r = nixWhy.whyNot {
              modules = defaultOnlyModules;
              inherit (defaultOnlyEval) options;
              path = "foo.enable";
            };
          in
          r.isExplicitlySet == false
          && (builtins.length r.defaultDefinitions) == 1
          && r.filteredOutDefinitions == [ ]
          && r.hint == null;
      }
      {
        name = "whyNot-filtered-by-mkIf";
        passed =
          let
            r = nixWhy.whyNot {
              modules = gatedModules;
              inherit (gatedEval) options;
              path = "foo.enable";
            };
          in
          r.isExplicitlySet == false && (builtins.length r.filteredOutDefinitions) >= 1 && r.hint != null;
      }
    ];

  v04Results = map (t: {
    inherit (t) name;
    inherit (t) passed;
  }) v04Tests;

  results = fixtureResults ++ v03Results ++ v04Results;
  failures = builtins.filter (r: !r.passed) results;
in
{
  inherit results failures;
  pass = failures == [ ];
  summary = "${toString (builtins.length results)} tests (${toString (builtins.length fixtureResults)} fixtures + ${toString (builtins.length v03Results)} v0.3 inline + ${toString (builtins.length v04Results)} v0.4 inline), ${toString (builtins.length failures)} failed";
}
