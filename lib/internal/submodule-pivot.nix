{ lib }:
let
  inherit (import ./apply-module.nix { inherit lib; }) applyFunctionModule;

  # Descend a config attrset along `parts`, preserving any _type wrappers
  # encountered on the way down. The result can be fed back as the
  # `config` of a synthetic module - lib.evalModules will rediscover
  # the wrappers and apply them correctly during the submodule's
  # internal merge.
  #
  # Returns null when the path does not exist in this config.
  descendWithWrappers =
    cfg: parts:
    if parts == [ ] then
      cfg
    else
      let
        ty = if builtins.isAttrs cfg then (cfg._type or null) else null;
        head = builtins.head parts;
        tail = builtins.tail parts;
      in
      if ty == "if" then
        let
          inner = descendWithWrappers cfg.content parts;
        in
        if inner == null then null else lib.mkIf cfg.condition inner
      else if ty == "override" then
        let
          inner = descendWithWrappers cfg.content parts;
        in
        if inner == null then null else lib.mkOverride cfg.priority inner
      else if ty == "merge" then
        let
          inners = builtins.filter (x: x != null) (map (c: descendWithWrappers c parts) cfg.contents);
        in
        if inners == [ ] then null else lib.mkMerge inners
      else if builtins.isAttrs cfg && cfg ? ${head} then
        descendWithWrappers cfg.${head} tail
      else
        null;

  # Normalize a module to its config attrset and source file. Function
  # modules are applied with capturedArgs; path modules are imported and
  # recursed. Returns null on failure.
  normalizeForExtract =
    capturedArgs: m:
    if builtins.isFunction m then
      let
        applied = applyFunctionModule m capturedArgs;
      in
      if applied == null then null else normalizeForExtract capturedArgs applied
    else if builtins.isPath m then
      let
        tried = builtins.tryEval (import m);
      in
      if !tried.success then
        null
      else
        let
          inner = normalizeForExtract capturedArgs tried.value;
        in
        if inner == null then null else inner // { file = inner.file or (toString m); }
    else if builtins.isAttrs m then
      {
        cfg = m.config or m;
        file = m._file or null;
      }
    else
      null;

  # For each user module, descend to `prefix` (preserving wrappers) and
  # return a synthetic module `{ _file, config = <descended> }`. Modules
  # that do not contain anything at the prefix are skipped.
  extractSyntheticModules =
    {
      modules,
      capturedArgs,
      prefix,
    }:
    let
      one =
        m:
        let
          normalized = normalizeForExtract capturedArgs m;
        in
        if normalized == null then
          null
        else
          let
            descended = descendWithWrappers normalized.cfg prefix;
          in
          if descended == null then
            null
          else
            {
              _file = if normalized.file != null then normalized.file else "<extracted>";
              config = descended;
            };
    in
    builtins.filter (m: m != null) (map one modules);

  # Detect whether `opt` is one of the submodule-flavored types we
  # support, and report how many path components the pivot consumes.
  #
  #   submodule              -> consumes 0 path components beyond the option;
  #                             remaining path is the sub-option path.
  #   attrsOf submodule      -> consumes 1 path component (the user-supplied
  #                             key); remaining path is the sub-option path
  #                             inside that key's instance.
  #   listOf submodule       -> not supported; documented limitation.
  classifySubmodule =
    opt:
    let
      typeName = opt.type.name or null;
      nestedName = opt.type.nestedTypes.elemType.name or null;
    in
    if typeName == "submodule" then
      {
        kind = "single";
        keyConsumes = 0;
      }
    else if typeName == "attrsOf" && nestedName == "submodule" then
      {
        kind = "attrsOf";
        keyConsumes = 1;
      }
    else
      {
        kind = "none";
        keyConsumes = 0;
      };
in
{
  inherit classifySubmodule extractSyntheticModules;

  # pivot :: { opt, modules, capturedArgs, prefix, remaining } -> { options, remainingAfter } | null
  #
  # Pivot through a submodule boundary at `opt`. `prefix` is the path
  # from the root options down to and including the option that holds
  # the submodule type. `remaining` is the path that continues inside
  # the submodule.
  #
  # For a single-instance submodule, the result options come from a
  # fresh lib.evalModules call with the submodule's own modules plus
  # synthetic modules extracted from the user's config at `prefix`.
  #
  # For an attrsOf submodule, the first element of `remaining` is the
  # user-supplied key. The pivot evaluates the per-key submodule with
  # synthetic modules extracted at `prefix ++ [ key ]`.
  #
  # Returns null when no submodule pivot applies.
  pivot =
    {
      opt,
      modules,
      capturedArgs,
      prefix,
      remaining,
    }:
    let
      cls = classifySubmodule opt;

      # Forward the captured module args the submodule's sub-modules may
      # reference (pkgs, specialArgs-derived, ...) via specialArgs.
      # config/options/lib are module-system-provided and must not be
      # overridden (passing the OUTER config as a submodule arg is wrong).
      forwardedArgs = builtins.removeAttrs capturedArgs [
        "config"
        "options"
        "lib"
      ];

      # Evaluate a submodule's modules in a guarded, seeded context.
      # `extraArgs` seeds `_module.args` (e.g. the attrsOf key as
      # `name`): a submodule sub-option whose default references `name`
      # (the users.users.<name> pattern) otherwise aborts uncatchably -
      # the `{ name, ... }:` function is applied without `name`.
      # evalModules is lazy and tryEval is shallow, so we force the
      # option-tree structure inside the guard; a broken construction
      # then returns null instead of aborting the walker downstream.
      evalSub =
        subModules: synthetic: extraArgs:
        let
          tried = builtins.tryEval (
            let
              res = lib.evalModules {
                modules =
                  subModules
                  ++ synthetic
                  ++ [
                    { config._module.check = false; }
                    { config._module.args = extraArgs; }
                  ];
                specialArgs = forwardedArgs;
              };
            in
            builtins.seq (builtins.attrNames res.options) res
          );
        in
        if tried.success then tried.value else null;
    in
    if cls.kind == "none" || remaining == [ ] then
      null
    else if cls.kind == "single" then
      let
        subModules = opt.type.getSubModules or [ ];
        synthetic = extractSyntheticModules {
          inherit modules capturedArgs prefix;
        };
        evaluated = evalSub subModules synthetic { };
      in
      if evaluated == null then
        null
      else
        {
          inherit (evaluated) options;
          inherit (evaluated) config;
          remainingAfter = remaining;
          # Pass synthetic modules forward so a *nested* submodule pivot
          # can extract its own definitions from them (the originals
          # were already consumed at the prefix level).
          syntheticModules = synthetic;
        }
    else if cls.kind == "attrsOf" then
      let
        key = builtins.head remaining;
        afterKey = builtins.tail remaining;
        # The submodule modules: same shape as single, but we're indexing
        # by a key, so synthetic modules extract at prefix ++ [key].
        subModules = opt.type.nestedTypes.elemType.getSubModules or [ ];
        synthetic = extractSyntheticModules {
          inherit modules capturedArgs;
          prefix = prefix ++ [ key ];
        };
        # Seed the attrsOf key as `name`, mirroring what the attrsOf /
        # submoduleWith machinery injects during a real evaluation.
        evaluated = evalSub subModules synthetic { name = key; };
      in
      if evaluated == null then
        null
      else
        {
          inherit (evaluated) options;
          inherit (evaluated) config;
          remainingAfter = afterKey;
          syntheticModules = synthetic;
        }
    else
      null;
}
