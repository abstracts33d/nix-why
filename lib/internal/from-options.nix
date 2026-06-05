{ lib }:
let
  submodulePivot = import ./submodule-pivot.nix { inherit lib; };
  priority = import ./priority.nix { inherit lib; };

  # Walk the options tree one path component at a time, pivoting
  # through submodule boundaries when encountered.
  #
  # On success returns { found = true; opt = <leaf option>; }, on
  # failure { found = false; }. Pivots consume the rest of the path
  # via recursion into the submodule's evaluated options tree.
  walkOptions =
    {
      options,
      pathParts,
      modules,
      capturedArgs,
      prefix,
    }:
    if pathParts == [ ] then
      {
        found = false;
      }
    else
      let
        head = builtins.head pathParts;
        tail = builtins.tail pathParts;
        nextPresent = builtins.isAttrs options && (options ? ${head});
      in
      if !nextPresent then
        { found = false; }
      else
        let
          next = options.${head};
          nextType = next._type or null;
          newPrefix = prefix ++ [ head ];
        in
        if nextType == "option" && tail == [ ] then
          # Leaf option reached.
          {
            found = true;
            opt = next;
          }
        else if nextType == "option" && tail != [ ] then
          # Path continues but we hit an option - try a submodule pivot.
          let
            pivoted = submodulePivot.pivot {
              opt = next;
              inherit modules capturedArgs;
              prefix = newPrefix;
              remaining = tail;
            };
          in
          if pivoted == null then
            { found = false; }
          else
            walkOptions {
              inherit (pivoted) options;
              pathParts = pivoted.remainingAfter;
              # After a pivot, the modules list resets to the synthetic
              # modules built by the pivot. A *nested* submodule pivot
              # encountered inside this evaluated subtree can then
              # extract its own definitions from those synthetic
              # modules, preserving per-module attribution across
              # arbitrary nesting depth.
              modules = pivoted.syntheticModules;
              inherit capturedArgs;
              prefix = [ ];
            }
        else if builtins.isAttrs next then
          # Not an option - keep descending the attrset.
          walkOptions {
            options = next;
            pathParts = tail;
            inherit modules capturedArgs;
            prefix = newPrefix;
          }
        else
          { found = false; };

  tryReadValue =
    opt:
    let
      tried = builtins.tryEval opt.value;
    in
    if tried.success then
      {
        inherit (tried) value;
        error = null;
      }
    else
      {
        value = null;
        error = "value evaluation failed - likely a merge conflict (mkForce collision, type mismatch, or submodule key collision)";
      };

  buildDeclarations =
    opt:
    let
      files = opt.declarations or [ ];
      positions = opt.declarationPositions or [ ];
      hasPositions = (builtins.length positions) >= (builtins.length files);
    in
    lib.imap0 (
      i: file:
      let
        p = if hasPositions then builtins.elemAt positions i else null;
      in
      {
        inherit file;
        line = if p == null then null else (p.line or null);
        column = if p == null then null else (p.column or null);
      }
    ) files;

  buildDefinitions =
    opt:
    let
      defs = opt.definitionsWithLocations or [ ];
      prio = opt.highestPrio or null;
    in
    map (def: {
      file = def.file or null;
      line = null;
      priority = prio;
      # Label via the single source (priority.nix), not null: the
      # options-surface path knows the winning priority number, so it
      # can name its kind. Per-def line/guard still need the module-walk.
      priorityKind = if prio == null then null else priority.labelFor prio;
      guardedBy = null;
      value = def.value or null;
      wins = true;
    }) defs;
in
{
  fromOptions =
    {
      options,
      pathParts,
      modules ? [ ],
      config ? { },
    }:
    let
      path = lib.concatStringsSep "." pathParts;
      tryArgs = builtins.tryEval (config._module.args or { });
      capturedArgs = (if tryArgs.success then tryArgs.value else { }) // {
        inherit lib config;
      };
      walked = walkOptions {
        inherit
          options
          pathParts
          modules
          capturedArgs
          ;
        prefix = [ ];
      };
    in
    if !walked.found then
      {
        inherit path;
        kind = "not-found";
        type = null;
        value = null;
        valueError = null;
        isDefined = false;
        winningPriority = null;
        declarations = [ ];
        definitions = [ ];
      }
    else
      let
        raw = walked.opt;
        isOption = raw != null && builtins.isAttrs raw && ((raw._type or null) == "option");
      in
      if !isOption then
        {
          inherit path;
          kind = "not-an-option";
          type = null;
          value = null;
          valueError = null;
          isDefined = false;
          winningPriority = null;
          declarations = [ ];
          definitions = [ ];
        }
      else
        let
          readResult = tryReadValue raw;
        in
        {
          inherit path;
          kind = "option";
          type = raw.type.name or null;
          inherit (readResult) value;
          valueError = readResult.error;
          isDefined = raw.isDefined or false;
          winningPriority = raw.highestPrio or null;
          declarations = buildDeclarations raw;
          definitions = buildDefinitions raw;
        };
}
