{ lib }:
let
  walker = import ./walker.nix { inherit lib; };
  priority = import ./priority.nix { inherit lib; };

  # Apply a function module with the captured _module.args. Two-step:
  # 1. Try calling with all captured args (works for `{ a, b, ... }: ...`
  #    where the function accepts varargs).
  # 2. If that throws "unexpected argument", filter to only the keys the
  #    function declares (works for `{ a, b }: ...`).
  # 3. If even the filtered call throws, give up - that module's
  #    contributions will not appear in the walk.
  applyFunctionModule =
    fn: capturedArgs:
    let
      argSpec = builtins.functionArgs fn;
      fullCall = builtins.tryEval (fn capturedArgs);
    in
    if fullCall.success then
      fullCall.value
    else
      let
        filteredArgs = lib.filterAttrs (n: _: argSpec ? ${n}) capturedArgs;
        filteredCall = builtins.tryEval (fn filteredArgs);
      in
      if filteredCall.success then filteredCall.value else null;

  # Normalize a single module entry to { cfg, file } or null when we
  # cannot evaluate it.
  #
  # Three shapes accepted:
  #   - Attrset modules: used directly (config sub-attr or top-level).
  #   - Path modules: imported, then recursed.
  #   - Function modules: applied with capturedArgs.
  normalizeModule =
    capturedArgs: m:
    if builtins.isPath m then
      let
        imported = import m;
        normalizedInner = normalizeModule capturedArgs imported;
      in
      if normalizedInner == null then
        null
      else
        normalizedInner // { file = normalizedInner.file or (toString m); }
    else if builtins.isFunction m then
      let
        applied = applyFunctionModule m capturedArgs;
      in
      if applied == null then null else normalizeModule capturedArgs applied
    else if builtins.isAttrs m then
      {
        cfg = m.config or m;
        file = m._file or null;
      }
    else
      null;

  allConditionsHeld = conditions: lib.all (c: c.condition) conditions;

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
            source = null;
            evaluatedTo = held;
            count = builtins.length conds;
          };
      inherit (leaf) value;
    };
in
{
  # fromModules :: { modules, config ? {}, pathParts } -> { definitions }
  #
  # Walks the supplied module list and returns the complete list of leaf
  # definitions encountered at the option path, including those filtered
  # out by mkIf or by priority.
  #
  # `config` is the evaluated configuration (typically the .config of
  # the lib.evalModules result). When non-empty, we read
  # `config._module.args` to recover the args lib.evalModules passed to
  # function modules during its own evaluation, and re-apply them when
  # walking function modules ourselves. When `config` is empty or has
  # no _module.args, function modules are still attempted with `{ lib;
  # config; }` as a minimal best-effort args set.
  fromModules =
    {
      modules,
      config ? { },
      pathParts,
    }:
    let
      tryArgs = builtins.tryEval (config._module.args or { });
      capturedArgs = (if tryArgs.success then tryArgs.value else { }) // {
        # Always provide lib and config; if the evaluator already had
        # them in _module.args these are no-ops.
        inherit lib config;
      };

      normalized = lib.filter (m: m != null) (map (normalizeModule capturedArgs) modules);

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
