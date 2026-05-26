{ lib }:
let
  # Safely read opt.value: returns null when the option is undefined or
  # when reading it throws (some defaults call `throw` to enforce required
  # configuration).
  tryReadValue =
    opt:
    if !(opt.isDefined or false) then
      null
    else
      let
        tried = builtins.tryEval opt.value;
      in
      if tried.success then tried.value else null;

  # Pair `opt.declarations` (list of file paths) with the matching entry
  # of `opt.declarationPositions` (list of { file, line, column }). Older
  # nixpkgs releases may not expose declarationPositions; in that case we
  # return file-only records.
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

  # Each surviving definition (post-mkIf, post-priority filter) is a
  # "winner" at the winning priority. from-modules.nix will later enrich
  # these with line numbers, priorityKind, and guardedBy details.
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
      priorityKind = null;
      guardedBy = null;
      value = def.value or null;
      wins = true;
    }) defs;
in
{
  # fromOptions :: { options, pathParts } -> AST
  #
  # Reads the publicly documented `options.<path>.*` attributes of an
  # evaluated NixOS-style option tree and returns a structured AST.
  # Does NOT touch any module-system internals; only the documented
  # option-type surface.
  fromOptions =
    {
      options,
      pathParts,
    }:
    let
      path = lib.concatStringsSep "." pathParts;
      raw = lib.attrByPath pathParts null options;
      isOption = raw != null && builtins.isAttrs raw && ((raw._type or null) == "option");
    in
    if raw == null then
      {
        inherit path;
        kind = "not-found";
        type = null;
        value = null;
        isDefined = false;
        winningPriority = null;
        declarations = [ ];
        definitions = [ ];
      }
    else if !isOption then
      {
        inherit path;
        kind = "not-an-option";
        type = null;
        value = null;
        isDefined = false;
        winningPriority = null;
        declarations = [ ];
        definitions = [ ];
      }
    else
      {
        inherit path;
        kind = "option";
        type = raw.type.name or null;
        value = tryReadValue raw;
        isDefined = raw.isDefined or false;
        winningPriority = raw.highestPrio or null;
        declarations = buildDeclarations raw;
        definitions = buildDefinitions raw;
      };
}
