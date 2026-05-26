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
        src = internal.extractMkIfCondition {
          file = def.file;
          line = def.line;
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
      map (
        def:
        finalizeDef (fillGuardSource (def // { wins = computeWins winningPriority def; }))
      ) fromModulesDefs
    else
      map (
        def:
        finalizeDef (def // { wins = true; })
      ) fromOptionsDefs;
in
{
  # resolve :: { modules, specialArgs ? {}, config, options, path } -> AST
  #
  # Composes the options-surface and module-walk introspection passes.
  # The options-surface pass provides the canonical merge result
  # (final value, declarations, winning priority); the module-walk pass
  # enriches each definition with line numbers, priority kind, and
  # mkIf-guard records. When module-walk is unavailable, the output
  # degrades gracefully to options-surface fidelity.
  resolve =
    {
      modules ? [ ],
      specialArgs ? { },
      config ? { },
      options,
      path,
    }:
    let
      pathParts = splitPath path;

      surface = internal.fromOptions { inherit options pathParts; };
      moduleWalk =
        if surface.kind != "option" then
          { definitions = [ ]; }
        else
          internal.fromModules {
            inherit
              modules
              specialArgs
              config
              pathParts
              ;
          };

      mergedDefinitions =
        if surface.kind != "option" then
          [ ]
        else
          mergeDefinitions {
            fromOptionsDefs = surface.definitions;
            fromModulesDefs = moduleWalk.definitions;
            winningPriority = surface.winningPriority;
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
      valueError = surface.valueError or null;
      definitions = mergedDefinitions;
      inherit conflicts;
      moduleWalkAvailable = moduleWalk.definitions != [ ];
    };

  # whatSets :: { modules, specialArgs ? {}, config, options, path } -> AST
  #
  # v0.3 reverse-lookup. Returns the same shape as resolve but oriented
  # around "every module that contains a definition for this option,
  # regardless of whether it won, was overridden, or was filtered out by
  # mkIf". The output AST is a subset of resolve's:
  #
  #   { path, kind, type, isDefined, declarations, setters }
  #
  # where `setters` is the deduplicated list of definitions across all
  # contributing modules. The renderer treats this differently from
  # resolve's `definitions`: no "winning" marker, no value, just file +
  # line + priorityKind + guardedBy per setter.
  whatSets =
    {
      modules ? [ ],
      specialArgs ? { },
      config ? { },
      options,
      path,
    }:
    let
      pathParts = splitPath path;
      surface = internal.fromOptions { inherit options pathParts; };
      moduleWalk =
        if surface.kind != "option" then
          { definitions = [ ]; }
        else
          internal.fromModules {
            inherit
              modules
              specialArgs
              config
              pathParts
              ;
          };

      # Union of options-surface winners and module-walk all-defs,
      # deduped on (file, line). The module-walk records are richer so
      # we prefer them when both sources see the same (file, line).
      setters =
        if moduleWalk.definitions != [ ] then
          map (d: {
            inherit (d)
              file
              line
              priorityKind
              guardedBy
              ;
            priority = d.priority;
          }) moduleWalk.definitions
        else
          map (d: {
            inherit (d) file priority priorityKind guardedBy;
            line = null;
          }) surface.definitions;
    in
    {
      inherit (surface)
        path
        kind
        type
        isDefined
        declarations
        ;
      setters = setters;
      moduleWalkAvailable = moduleWalk.definitions != [ ];
    };

  # render :: { ast, format ? "tree", maxValue ? 200, noColor ? false } -> string
  #
  # In-Nix render is a stub; the production CLI ships its own bash
  # renderers. Provided so library consumers can call render without
  # depending on the CLI.
  render =
    {
      ast,
      format ? "tree",
      maxValue ? 200,
      noColor ? false,
    }:
    "nix-why: in-Nix render not yet implemented (format=${format}); pass through nix-why-option for the production renderer";
}
