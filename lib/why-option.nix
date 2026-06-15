{ lib, internal }:
let
  splitPath = path: lib.splitString "." path;

  # A definition wins iff it survives both the priority filter AND every
  # mkIf condition on its way down evaluated true.
  computeWins =
    winningPriority: def:
    let
      priorityOk = def.priority == winningPriority;
      guardOk = def.guardedBy == null || def.guardedBy.evaluatedTo;
    in
    priorityOk && guardOk;

  # Replace `guardedBy.source = null` with the extracted source text
  # (when extraction succeeds). Best-effort; on failure leaves null.
  fillGuardSource =
    def:
    if def.guardedBy == null then
      def
    else
      let
        # Scan from the guard's own recorded position (set by the walker),
        # not the leaf - the leaf sits past the mkIf token. Falls back to
        # the leaf position only when no guard position was captured.
        gp = def.guardSource or null;
        src =
          if gp != null then
            internal.extractMkIfCondition {
              inherit (gp) file line;
              column = gp.column or 1;
            }
          else
            internal.extractMkIfCondition {
              inherit (def) file line;
              column = def.column or 1;
            };
      in
      def
      // {
        guardedBy = {
          inherit (def.guardedBy) evaluatedTo;
          source = src;
        };
      };

  # Drop transient fields and ensure JSON-friendly shape.
  finalizeDef = def: {
    inherit (def)
      file
      line
      priority
      priorityKind
      guardedBy
      value
      wins
      ;
  };

  # Merge from-options (canonical winners, file-only) with from-modules
  # (all defs incl. losers, with full line + priority + guard info).
  #
  # When the module-walk produced nothing (adapter could not recover the
  # raw modules), we fall back to options-surface output: each surviving
  # definition is rendered as a winner with line/priorityKind/guardedBy
  # left null and a single stderr-style warning emitted.
  mergeDefinitions =
    {
      fromOptionsDefs,
      fromModulesDefs,
      winningPriority,
    }:
    let
      useModuleWalk = fromModulesDefs != [ ];
    in
    if useModuleWalk then
      let
        walkDefs = map (
          def: finalizeDef (fillGuardSource (def // { wins = computeWins winningPriority def; }))
        ) fromModulesDefs;
        walkFiles = map (d: d.file) walkDefs;
        walkHasWinner = lib.any (d: d.wins) walkDefs;
        # Union: append surface definitions the flat walk could not see
        # (transitively-imported modules). The surface side carries no
        # per-def line, so file is the only stable dedup key. These
        # recover the canonical winner when the walk found only losers;
        # if the walk already has a winner they are kept for completeness
        # but not re-marked as winners.
        surfaceExtras = lib.filter (d: !(builtins.elem d.file walkFiles)) fromOptionsDefs;
        extraDefs = map (def: finalizeDef (def // { wins = !walkHasWinner && def.wins; })) surfaceExtras;
      in
      walkDefs ++ extraDefs
    else
      map (def: finalizeDef (def // { wins = true; })) fromOptionsDefs;

  # The mkOptionDefault priority that nixpkgs assigns to an option's
  # declared `default`. Treating this as "not a user definition" is what
  # lets whyNot distinguish explicit configuration from type defaults.
  mkOptionDefaultPriority = 1500;

  isTypeDefault = def: def.priority == mkOptionDefaultPriority;

  isFilteredByMkIf = def: def.guardedBy != null && def.guardedBy.evaluatedTo == false;
in
rec {
  /**
    Resolve a single option path against an evaluated module-system
    configuration. Returns the final value plus every contributing
    definition, with file:line, priority kind, and `mkIf` guards.

    Composes two introspection passes:

    - **options-surface** (always available): canonical merge result
      from the evaluated `options` tree — final value, declarations,
      winning priority.
    - **module-walk** (opt-in): re-walks the raw modules list to
      attach per-definition line numbers, priority kind labels, and
      `mkIf`-guard records. Requires `_module.args.modules` to be
      set in the configuration (see adapters' module-recovery
      contract).

    When module-walk is unavailable, the output degrades gracefully
    to options-surface fidelity (no per-definition line numbers, no
    guard records). `moduleWalkAvailable` in the result indicates
    which mode was used.

    Module-walk resolves only for FLAT module lists. Deeply imported
    configurations degrade even with `_module.args.modules` set: the
    recovered top-level list does not carry transitively imported
    definitions, and the module system exposes neither per-definition
    positions nor mkIf-filtered candidates natively. Closing that gap
    natively is the upstream-RFC target; the walk is not extended to
    re-implement `collectModules` (that coupling is a non-goal).

    # Inputs

    `modules`
    : Raw modules list. Optional; pass `[]` (or omit) when the
      adapter could not recover it. The merge step then falls back
      to options-surface fidelity.

    `config`
    : Evaluated config from `lib.evalModules`. `from-modules` reads
      its `_module.args` to apply function-shaped modules
      accurately.

    `options`
    : Evaluated options tree from `lib.evalModules`.

    `path`
    : Dotted option path, e.g. `"services.openssh.enable"`.

    # Type

    ```
    resolve :: {
      modules ? [Module],
      config ? AttrSet,
      options :: AttrSet,
      path :: String,
    } -> AST
    ```

    Where `AST` is the shape documented at
    [`docs/reference/json-schema.md`](../docs/reference/json-schema.md)
    under the `nix-why-option` (resolve) section.

    # Example

    ```nix
    nixWhy.resolve {
      inherit (adapted) modules config options;
      path = "services.openssh.enable";
    }
    # => { path = "services.openssh.enable"; kind = "option";
    #      value = true; winningPriority = 100; isDefined = true;
    #      definitions = [ … ]; conflicts = []; … }
    ```
  */
  resolve =
    {
      modules ? [ ],
      config ? { },
      options,
      path,
    }:
    let
      pathParts = splitPath path;

      surface = internal.fromOptions {
        inherit
          options
          pathParts
          modules
          config
          ;
      };
      moduleWalk =
        if surface.kind != "option" then
          { definitions = [ ]; }
        else
          internal.fromModules {
            inherit modules pathParts config;
          };

      mergedDefinitions =
        if surface.kind != "option" then
          [ ]
        else
          mergeDefinitions {
            fromOptionsDefs = surface.definitions;
            fromModulesDefs = moduleWalk.definitions;
            inherit (surface) winningPriority;
          };

      # An unresolvable merge surfaces as a non-null surface.valueError
      # (tryEval failed on opt.value). The conflicts block lists the
      # definitions that were involved at the winning priority.
      conflicts =
        if surface.kind == "option" && (surface.valueError or null) != null then
          [
            {
              kind = "merge-conflict";
              message = surface.valueError;
              involvedDefinitions = lib.filter (d: d.wins) mergedDefinitions;
            }
          ]
        else
          [ ];
    in
    {
      inherit (surface)
        path
        kind
        type
        value
        isDefined
        winningPriority
        declarations
        ;
      # Label for the winning priority, from the single source
      # (priority.nix). Lets the renderer drop its duplicate bash table.
      winningPriorityKind =
        if surface.winningPriority == null then null else internal.labelFor surface.winningPriority;
      valueError = surface.valueError or null;
      definitions = mergedDefinitions;
      inherit conflicts;
      moduleWalkAvailable = moduleWalk.definitions != [ ];
    };

  /**
    Reverse-lookup for an option path: list every module that
    contributes a definition, regardless of whether it won the
    merge, was overridden, or was filtered out by `mkIf`.

    Useful for "where on earth is this being set?" questions, where
    `resolve`'s winner-centric view hides the losers. The renderer
    treats `setters` differently from `resolve.definitions`: no
    winning marker, no merged value, just per-setter file + line +
    priorityKind + guardedBy.

    # Inputs

    Same as [`resolve`](#resolve).

    # Type

    ```
    whatSets :: {
      modules ? [Module],
      config ? AttrSet,
      options :: AttrSet,
      path :: String,
    } -> {
      path :: String,
      kind :: "option" | "not-found" | "not-an-option",
      type :: String,
      isDefined :: Bool,
      declarations :: [{ file, line, column }],
      setters :: [Setter],
      moduleWalkAvailable :: Bool,
    }
    ```

    Where `Setter` is `{ file, line, priority, priorityKind,
    guardedBy, value }`.
  */
  whatSets =
    {
      modules ? [ ],
      config ? { },
      options,
      path,
    }:
    let
      pathParts = splitPath path;
      surface = internal.fromOptions {
        inherit
          options
          pathParts
          modules
          config
          ;
      };
      moduleWalk =
        if surface.kind != "option" then
          { definitions = [ ]; }
        else
          internal.fromModules {
            inherit modules pathParts config;
          };

      surfaceSetter = d: {
        inherit (d)
          file
          priority
          priorityKind
          guardedBy
          value
          ;
        line = null;
      };
      # Union of module-walk all-defs (richer: line + guard) with the
      # options-surface setters the flat walk could not see (transitively
      # imported modules). Deduped on file - the surface side has no line.
      # The module-walk records are preferred when both sources see a file.
      setters =
        if moduleWalk.definitions == [ ] then
          map surfaceSetter surface.definitions
        else
          let
            walkSetters = map (d: {
              inherit (d)
                file
                line
                priority
                priorityKind
                guardedBy
                value
                ;
            }) moduleWalk.definitions;
            walkFiles = map (s: s.file) walkSetters;
            surfaceExtras = lib.filter (d: !(builtins.elem d.file walkFiles)) surface.definitions;
          in
          walkSetters ++ map surfaceSetter surfaceExtras;
    in
    {
      inherit (surface)
        path
        kind
        type
        isDefined
        declarations
        ;
      inherit setters;
      moduleWalkAvailable = moduleWalk.definitions != [ ];
    };

  /**
    Explain why an option is *not* explicitly set, and what would
    set it under different conditions.

    NixOS treats an option's declared `default` as a definition at
    priority `1500` (`mkOptionDefault`), so a plain `resolve`
    reports `isDefined = true` even when no module touched the
    option. `whyNot` filters that out: only definitions with
    priority `≠ 1500` count as user-supplied. It additionally
    surfaces `mkIf`-filtered definitions that *would* have set the
    option if their guards had held.

    Typical user question this answers:

    > "I set `services.foo.enable = true` but `services.foo.port`
    > comes out as the default. Why?"

    `whyNot services.foo.port` will list the mkIf-gated definitions
    of `services.foo.port` and the condition they require.

    # Inputs

    Same as [`resolve`](#resolve). `modules` is strongly recommended
    here (without module-walk, `filteredOutDefinitions` is always
    empty since `mkIf` guards live in the module source, not the
    options surface).

    # Type

    ```
    whyNot :: { modules, config, options, path } -> {
      path, kind, type, value, declarations, moduleWalkAvailable,
      isExplicitlySet :: Bool,
      explicitDefinitions :: [Def],
      defaultDefinitions  :: [Def],
      filteredOutDefinitions :: [Def],
      hint :: String | null,
    }
    ```

    `isExplicitlySet` is true iff `explicitDefinitions` is non-
    empty, *independent* of whether any of those definitions won
    the merge.
  */
  whyNot =
    args:
    let
      base = resolve args;
      defs = base.definitions or [ ];

      # "Explicit" means user-supplied AND surviving any mkIf guards on
      # the way down. A definition that is non-default-priority but
      # gated out by a false mkIf is not an explicit configuration -
      # it's a candidate that did not fire, and belongs in
      # filteredOutDefinitions instead.
      explicitDefinitions = lib.filter (d: !isTypeDefault d && !isFilteredByMkIf d) defs;
      defaultDefinitions = lib.filter isTypeDefault defs;
      filteredOutDefinitions = lib.filter isFilteredByMkIf defs;

      isExplicitlySet = explicitDefinitions != [ ];

      describeFiltered =
        d:
        let
          pos = if d.line == null then d.file else "${d.file}:${toString d.line}";
          condSrc = if d.guardedBy.source == null then "<unknown condition>" else d.guardedBy.source;
        in
        "${pos} (would set when ${condSrc})";

      hint =
        if isExplicitlySet || filteredOutDefinitions == [ ] then
          null
        else
          "this option is not explicitly set; the following definitions would set it if their conditions held: "
          + lib.concatStringsSep "; " (map describeFiltered filteredOutDefinitions);
    in
    {
      inherit (base)
        path
        kind
        type
        value
        declarations
        moduleWalkAvailable
        ;
      inherit
        isExplicitlySet
        explicitDefinitions
        defaultDefinitions
        filteredOutDefinitions
        hint
        ;
    };

  /**
    Fuzzy-match an option-path pattern against the options tree,
    descending into submodules.

    Walks the options tree depth-first collecting every leaf option
    (`_type == "option"`), then filters by infix match against the
    dotted path. For options whose type is `submodule` (or
    `attrsOf submodule`), the search descends into the submodule's
    declared sub-options via `getSubOptions []`. `attrsOf submodule`
    sub-options are exposed under the key placeholder `"<name>"`
    so they remain searchable.

    Recursion into submodules is bounded by `maxSubmoduleDepth`
    (default `2`) to keep eval time reasonable on configurations
    with deeply nested submodule chains (e.g. nixpkgs' `services.*`
    with `attrsOf submodule of attrsOf submodule of …`).

    # Inputs

    `options`
    : Evaluated options tree.

    `pattern`
    : Infix substring to match against each dotted option path.

    `limit`
    : Maximum matches in the returned `matches` list. `0` disables
      truncation. Default `50`.

    `maxSubmoduleDepth`
    : Maximum number of submodule pivots from the root options
      tree. Default `2`.

    # Type

    ```
    search :: {
      options :: AttrSet,
      pattern :: String,
      limit ? 50 :: Int,
      maxSubmoduleDepth ? 2 :: Int,
    } -> {
      pattern :: String,
      matches :: [{ path, type, declarations, isDefined }],
      totalMatches :: Int,
      truncated :: Bool,
    }
    ```
  */
  search =
    {
      options,
      pattern,
      limit ? 50,
      maxSubmoduleDepth ? 2,
    }:
    let
      # Best-effort force: return `default` when evaluating `e` throws a
      # CATCHABLE error. (Uncatchable aborts - e.g. attribute-missing -
      # still propagate; search cannot guard those.)
      tryOr =
        default: e:
        let
          t = builtins.tryEval e;
        in
        if t.success then t.value else default;

      # Walk into the sub-options tree of a submodule-typed option.
      # Returns an attrset of sub-options on success, null on any
      # eval failure (so search stays robust against odd type configs).
      # getSubOptions is forced to its key structure INSIDE the tryEval
      # (it is lazy; a shallow tryEval would defer a malformed result's
      # throw to the caller).
      subOptionsOf =
        opt:
        let
          typeName = tryOr null (opt.type.name or null);
          forceKeys = s: builtins.seq (builtins.attrNames s) s;
          subOptsTried =
            if typeName == "submodule" then
              builtins.tryEval (forceKeys (opt.type.getSubOptions [ ]))
            else if
              typeName == "attrsOf" && (tryOr null (opt.type.nestedTypes.elemType.name or null)) == "submodule"
            then
              builtins.tryEval (forceKeys (opt.type.nestedTypes.elemType.getSubOptions [ ]))
            else
              { success = false; };
        in
        if subOptsTried.success && builtins.isAttrs subOptsTried.value then subOptsTried.value else null;

      # `depth` counts how many submodule pivots we've taken from the
      # root options tree. Each submodule expansion consumes one
      # depth budget. Limit prevents pathological blow-up on options
      # trees with deeply nested submodule chains (e.g. nixpkgs'
      # services.* with attrsOf submodule of attrsOf submodule of ...).
      collectAllOptions =
        depth: prefix: attrs:
        let
          names = builtins.attrNames attrs;
        in
        lib.concatMap (
          name:
          let
            value = attrs.${name};
            here = prefix ++ [ name ];
            herePath = lib.concatStringsSep "." here;
            isAttr = builtins.isAttrs value;
            isOption = isAttr && ((value._type or null) == "option");
            isContainer = isAttr && !isOption;
            # For submodule-typed options, descend into their
            # sub-options - but only while the depth budget allows.
            # The placeholder `<name>` is appended for attrsOf
            # submodule sub-paths so they remain queryable.
            subOpts = if isOption && depth > 0 then subOptionsOf value else null;
            subPrefix =
              if isOption && (tryOr null (value.type.name or null)) == "attrsOf" then
                here ++ [ "<name>" ]
              else
                here;
          in
          if isOption then
            (
              [
                # path never needs forcing (built from names), so a match
                # is always reported even when an option's metadata is
                # un-evaluable on a given config. Metadata is best-effort.
                {
                  path = herePath;
                  type = tryOr null (value.type.name or null);
                  declarations = tryOr [ ] (value.declarations or [ ]);
                  isDefined = tryOr false (value.isDefined or false);
                }
              ]
              ++ (if subOpts == null then [ ] else collectAllOptions (depth - 1) subPrefix subOpts)
            )
          else if isContainer then
            collectAllOptions depth here value
          else
            [ ]
        ) names;

      all = collectAllOptions maxSubmoduleDepth [ ] options;
      matches = lib.filter (entry: lib.hasInfix pattern entry.path) all;
      total = builtins.length matches;
      truncated = limit > 0 && total > limit;
      shown = if truncated then lib.sublist 0 limit matches else matches;
    in
    {
      inherit pattern truncated;
      matches = shown;
      totalMatches = total;
    };

}
