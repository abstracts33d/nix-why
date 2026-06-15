{
  pkgs ? import <nixpkgs> { },
}:
let
  inherit (pkgs) lib;
  nixWhy = import ../lib { inherit lib; };
  # Internal: the source-text extractor, tested directly in the #6
  # parser regression set below (it is not part of the public API).
  nixSource = import ../lib/internal/nix-source.nix { inherit lib; };

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
    "submodule-name-arg"
    # #18 merge-semantics fidelity
    "order-wrapper"
    "mkif-parent-guard"
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

  # Drift guard. The walker (lib/internal/walker.nix) hardcodes the
  # module-system `_type` markers and their field names; the priority
  # table (lib/internal/priority.nix) hardcodes the priority numbers.
  # Both are nixpkgs internals (`builtins.unsafeGetAttrPos`-adjacent,
  # unstable). These assertions pin them against the LIVE nixpkgs lib so
  # a release that renames a marker or renumbers a priority fails LOUDLY
  # here instead of silently degrading the module-walk. This coupling is
  # what RFC #2 (native provenance) would remove; until then this guard
  # is the early-warning. See lib/internal/{walker,priority}.nix.
  driftTests =
    let
      prioModules = [
        {
          options.x = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "drift";
          };
        }
        { config.x = 1; } # plain, unwrapped -> module-system default priority
      ];
      prioEval = lib.evalModules { modules = prioModules ++ [ permissive ]; };
      plainWinningPriority =
        (nixWhy.resolve {
          modules = prioModules;
          inherit (prioEval) options config;
          path = "x";
        }).winningPriority;
    in
    [
      {
        name = "drift-type-if";
        passed =
          (lib.mkIf true 1)._type == "if" && (lib.mkIf true 1) ? condition && (lib.mkIf true 1) ? content;
      }
      {
        name = "drift-type-override";
        passed =
          (lib.mkForce 1)._type == "override" && (lib.mkForce 1) ? priority && (lib.mkForce 1) ? content;
      }
      {
        name = "drift-type-merge";
        passed = (lib.mkMerge [ 1 ])._type == "merge" && (lib.mkMerge [ 1 ]) ? contents;
      }
      {
        name = "drift-type-order";
        passed =
          (lib.mkBefore [ 1 ])._type == "order"
          && (lib.mkBefore [ 1 ]) ? content
          && (lib.mkBefore [ 1 ]).priority == 500
          && (lib.mkAfter [ 1 ]).priority == 1500;
      }
      {
        name = "drift-prio-mkVMOverride-10";
        passed = (lib.mkVMOverride 1).priority == 10;
      }
      {
        name = "drift-prio-mkForce-50";
        passed = (lib.mkForce 1).priority == 50;
      }
      {
        name = "drift-prio-mkImageMediaOverride-60";
        passed = (lib.mkImageMediaOverride 1).priority == 60;
      }
      {
        name = "drift-prio-default-100";
        passed = plainWinningPriority == 100;
      }
      {
        name = "drift-prio-mkDefault-1000";
        passed = (lib.mkDefault 1).priority == 1000;
      }
      {
        name = "drift-prio-mkOptionDefault-1500";
        passed = (lib.mkOptionDefault 1).priority == 1500;
      }
    ];

  driftResults = map (t: {
    inherit (t) name;
    inherit (t) passed;
  }) driftTests;

  # #6: nix-source parser regression + graceful-fallback guard. The
  # extractor (lib/internal/nix-source.nix) is best-effort: a hand-rolled
  # bracket matcher over readFile'd module source, riding the unstable
  # builtins.unsafeGetAttrPos. These pin its output on committed real
  # source samples and confirm it returns null (never throws) on the
  # absent / unreadable cases - including a missing file, which
  # builtins.tryEval alone does NOT guard (hence the pathExists gate).
  sourceTests =
    let
      extract = nixSource.extractMkIfCondition;
      sample = name: ./fixtures/source-samples + "/${name}.nix";
    in
    [
      {
        name = "source-paren-condition";
        passed =
          extract {
            file = sample "paren";
            line = 1;
            column = 1;
          } == "config.foo && config.bar";
      }
      {
        name = "source-dotted-condition";
        passed =
          extract {
            file = sample "dotted";
            line = 1;
            column = 1;
          } == "config.feature.enabled";
      }
      {
        name = "source-no-mkif-null";
        passed =
          extract {
            file = sample "no-mkif";
            line = 1;
            column = 1;
          } == null;
      }
      {
        name = "source-null-file-null";
        passed =
          extract {
            file = null;
            line = 1;
            column = 1;
          } == null;
      }
      {
        name = "source-null-position-null";
        passed =
          extract {
            file = sample "paren";
            line = null;
            column = null;
          } == null;
      }
      {
        name = "source-missing-file-null";
        passed =
          extract {
            file = sample "does-not-exist";
            line = 1;
            column = 1;
          } == null;
      }
    ];

  sourceResults = map (t: {
    inherit (t) name;
    inherit (t) passed;
  }) sourceTests;

  # #10: priority labels come from the single lib source (priority.nix)
  # on the options-surface path too - not just the module-walk - and the
  # option-level winningPriorityKind is emitted. Pins the SSOT so the
  # deleted bash priority_label table stays deleted.
  ssotTests =
    let
      mods = [
        {
          options.foo.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "ssot";
          };
        }
        { config.foo.enable = lib.mkDefault true; }
      ];
      ev = lib.evalModules { modules = mods ++ [ permissive ]; };
      # modules = [] forces the options-surface path (no module-walk).
      r = nixWhy.resolve {
        modules = [ ];
        inherit (ev) options config;
        path = "foo.enable";
      };
    in
    [
      {
        name = "ssot-winning-priority-kind";
        passed = r.winningPriorityKind == "mkDefault";
      }
      {
        name = "ssot-options-surface-priority-kind";
        passed = r.definitions != [ ] && builtins.all (d: d.priorityKind == "mkDefault") r.definitions;
      }
    ];

  ssotResults = map (t: {
    inherit (t) name;
    inherit (t) passed;
  }) ssotTests;

  # Crash-fix regression tests. These reproduce uncatchable evaluation
  # aborts the module-walk hit on real configs (builtins.tryEval does
  # NOT catch "called without required argument"). Each must RESOLVE
  # (not abort) for the suite to even evaluate.
  crashFixTests =
    let
      # A function module requiring a specialArg. evalModules supplies it
      # via specialArgs, so the config evaluates; but the arg is NOT in
      # config._module.args, so nix-why's module-walk re-application lacks
      # it. Pre-fix: `builtins.tryEval (fn capturedArgs)` could not catch
      # the "missing required argument" abort and resolve crashed
      # wholesale. Post-fix: the un-appliable module is skipped, the plain
      # definition still resolves.
      specialArgModules = [
        {
          options.foo.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "test";
          };
          config.foo.enable = true;
        }
        (
          { mySpecialArg, ... }:
          {
            config.foo.enable = lib.mkForce mySpecialArg;
          }
        )
      ];
      specialArgEval = lib.evalModules {
        modules = specialArgModules ++ [ permissive ];
        specialArgs = {
          mySpecialArg = false;
        };
      };
      specialArgAst = nixWhy.resolve {
        modules = specialArgModules;
        inherit (specialArgEval) options config;
        path = "foo.enable";
      };
    in
    [
      {
        name = "crashfix-specialarg-module-skipped-not-aborted";
        # resolve completes; surface value is the merged truth (mkForce
        # false applied by evalModules), and the walk kept the plain
        # `config.foo.enable = true` definition rather than aborting.
        passed =
          specialArgAst.kind == "option"
          && specialArgAst.value == false
          && builtins.any (d: d.value == true) specialArgAst.definitions;
      }
    ];

  crashFixResults = map (t: {
    inherit (t) name;
    inherit (t) passed;
  }) crashFixTests;

  # #18 definitions-union test. The module-walk only sees the flat
  # `modules` list; a definition contributed by a module absent from it
  # (the transitively-imported case) is invisible to the walk but present
  # on the options surface - including, as here, the actual merge winner.
  # Pre-fix mergeDefinitions was either/or: the moment the walk found
  # anything it discarded the surface set, so the winner vanished and no
  # definition reported wins=true. Post-fix the two sets are unioned
  # (surface defs whose file the walk did not see are appended).
  unionTests =
    let
      declModule = {
        options.foo.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "test";
        };
      };
      # Loser, seen by the walk.
      aModule = {
        _file = "/virtual/a.nix";
        config.foo.enable = lib.mkDefault false;
      };
      # Winner, NOT in the list passed to resolve (simulates a
      # transitively-imported module the flat walk cannot see).
      bModule = {
        _file = "/virtual/b.nix";
        config.foo.enable = lib.mkForce true;
      };
      ev = lib.evalModules {
        modules = [
          declModule
          aModule
          bModule
          permissive
        ];
      };
      ast = nixWhy.resolve {
        modules = [
          declModule
          aModule
        ];
        inherit (ev) options config;
        path = "foo.enable";
      };
    in
    [
      {
        name = "union-surface-winner-recovered";
        passed =
          ast.value == true
          && builtins.any (d: d.wins) ast.definitions
          && builtins.any (d: d.value == true) ast.definitions;
      }
    ];

  unionResults = map (t: {
    inherit (t) name;
    inherit (t) passed;
  }) unionTests;

  results =
    fixtureResults
    ++ v03Results
    ++ v04Results
    ++ driftResults
    ++ sourceResults
    ++ ssotResults
    ++ crashFixResults
    ++ unionResults;
  failures = builtins.filter (r: !r.passed) results;
in
{
  inherit results failures;
  pass = failures == [ ];
  summary = "${toString (builtins.length results)} tests (${toString (builtins.length fixtureResults)} fixtures + ${toString (builtins.length v03Results)} v0.3 inline + ${toString (builtins.length v04Results)} v0.4 inline + ${toString (builtins.length driftResults)} drift-guard + ${toString (builtins.length sourceResults)} source-parse + ${toString (builtins.length ssotResults)} ssot + ${toString (builtins.length crashFixResults)} crash-fix + ${toString (builtins.length unionResults)} union), ${toString (builtins.length failures)} failed";
}
