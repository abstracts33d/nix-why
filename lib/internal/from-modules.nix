{ lib }:
let
  walker = import ./walker.nix { inherit lib; };
  priority = import ./priority.nix { inherit lib; };

  # Normalize a single module entry to { cfg, file } or null when we
  # cannot safely handle it.
  #
  # Function modules require evaluation arguments we may not have; rather
  # than guessing, we skip them and rely on the upstream adapter to
  # pre-apply functional modules (or for callers to use the `raw` adapter
  # with a pre-resolved module list).
  normalizeModule =
    m:
    if builtins.isPath m then
      let
        imported = import m;
      in
      if builtins.isAttrs imported then
        {
          cfg = imported.config or imported;
          file = toString m;
        }
      else
        null
    else if builtins.isAttrs m then
      {
        cfg = m.config or m;
        file = m._file or null;
      }
    else
      null;

  # Conditions are collected outer-to-inner during the walk. A definition
  # "passes" all its mkIf guards iff every condition evaluated true.
  allConditionsHeld = conditions: lib.all (c: c.condition) conditions;

  # Build a definition record from a walker leaf.
  #
  # `file` argument is the surrounding module's source file, used as a
  # fallback when the leaf's own position (from unsafeGetAttrPos) lacks
  # one - typically the case for compound-attribute paths whose outermost
  # attribute was already in a synthetic level.
  buildDefinition =
    file: leaf:
    let
      posFile = if leaf.pos == null then null else (leaf.pos.file or null);
      line = if leaf.pos == null then null else (leaf.pos.line or null);
      column = if leaf.pos == null then null else (leaf.pos.column or null);
      conds = leaf.ctx.conditions;
      held = allConditionsHeld conds;
    in
    {
      file = if posFile != null then posFile else file;
      inherit line column;
      priority = leaf.ctx.priority;
      priorityKind = priority.labelFor leaf.ctx.priority;
      guardedBy =
        if conds == [ ] then
          null
        else
          {
            # The condition's textual source is filled in by the
            # nix-source extractor (commit 7) when available.
            source = null;
            evaluatedTo = held;
            count = builtins.length conds;
          };
      inherit (leaf) value;
    };
in
{
  # fromModules :: { modules, specialArgs ? {}, config ? {}, pathParts } -> { definitions }
  #
  # Walks the supplied module list (post-normalization) and returns the
  # complete list of leaf definitions encountered at the option path,
  # including those filtered out later by mkIf or by priority.
  #
  # When the module list is empty (e.g. NixOS adapter could not recover
  # the raw modules), returns an empty definitions list. The merge step
  # in why-option.nix degrades the output gracefully in that case.
  fromModules =
    {
      modules,
      pathParts,
    }:
    let
      normalized = lib.filter (m: m != null) (map normalizeModule modules);
      perModuleDefs =
        m:
        let
          leaves = walker.walkConfig {
            config = m.cfg;
            inherit pathParts;
          };
        in
        map (buildDefinition m.file) leaves;
      definitions = lib.concatMap perModuleDefs normalized;
    in
    {
      inherit definitions;
    };
}
