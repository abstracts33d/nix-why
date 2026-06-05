{ lib }:
let
  # 1-indexed (line, column) -> character offset in `content`. Mirrors
  # the convention used by builtins.unsafeGetAttrPos.
  computeOffset =
    content: line: column:
    let
      lines = lib.splitString "\n" content;
      linesBefore = lib.sublist 0 (line - 1) lines;
      sumLines = lib.foldl' (acc: l: acc + (builtins.stringLength l) + 1) 0 linesBefore;
    in
    sumLines + (column - 1);

  # Index of the matching close bracket starting at index 0, or null on
  # mismatch. The input must start with `open`.
  matchBracket =
    open: close: str:
    let
      n = builtins.stringLength str;
      go =
        depth: idx:
        if idx >= n then
          null
        else
          let
            c = builtins.substring idx 1 str;
          in
          if c == open then
            go (depth + 1) (idx + 1)
          else if c == close then
            (if depth == 1 then idx else go (depth - 1) (idx + 1))
          else
            go depth (idx + 1);
    in
    if n == 0 || (builtins.substring 0 1 str) != open then null else go 1 1;

  skipWS =
    str:
    let
      n = builtins.stringLength str;
      go =
        idx:
        if idx >= n then
          idx
        else
          let
            c = builtins.substring idx 1 str;
          in
          if c == " " || c == "\t" || c == "\n" || c == "\r" then go (idx + 1) else idx;
      end = go 0;
    in
    builtins.substring end (-1) str;

  # Extract a primary expression from the start of `str`. Returns the
  # expression text or null on parse failure. Best-effort - covers the
  # common shapes:
  #   ( expr )                      -> contents (parens stripped)
  #   { attrset }                   -> kept verbatim with braces
  #   identifier[.identifier ...]   -> dotted path
  extractPrimary =
    str:
    if builtins.stringLength str == 0 then
      null
    else
      let
        first = builtins.substring 0 1 str;
      in
      if first == "(" then
        let
          idx = matchBracket "(" ")" str;
        in
        if idx == null then null else builtins.substring 1 (idx - 1) str
      else if first == "{" then
        let
          idx = matchBracket "{" "}" str;
        in
        if idx == null then null else builtins.substring 0 (idx + 1) str
      else
        let
          n = builtins.stringLength str;
          isIdCh =
            c:
            (c >= "a" && c <= "z")
            || (c >= "A" && c <= "Z")
            || (c >= "0" && c <= "9")
            || c == "_"
            || c == "-"
            || c == ".";
          go =
            idx:
            if idx >= n then
              idx
            else if isIdCh (builtins.substring idx 1 str) then
              go (idx + 1)
            else
              idx;
          end = go 0;
        in
        if end == 0 then null else builtins.substring 0 end str;

  # Read a file, returning null instead of throwing on any failure.
  # builtins.tryEval does NOT catch builtins.readFile's "No such file"
  # IO error (same tryEval gap as missing-argument errors), so guard
  # with pathExists FIRST; tryEval then covers restricted/pure-eval
  # "access forbidden" throws. Without the pathExists guard a stale
  # source position (file since deleted/moved) would crash the walk.
  tryReadFile =
    file:
    let
      tried = builtins.tryEval (if builtins.pathExists file then builtins.readFile file else null);
    in
    if tried.success then tried.value else null;
in
{
  # extractMkIfCondition :: { file, line, column } -> string | null
  #
  # Best-effort source extraction. Given the source position of an
  # attribute that was guarded by mkIf, reads the source file and tries
  # to recover the textual condition expression as it appears in code.
  #
  # Failure modes (all return null, never throw):
  #   - file is null / cannot be read (pure-eval restrictions, missing)
  #   - position cannot be located
  #   - no `mkIf` token found near the position
  #   - the condition expression is too complex for the parser
  #
  # LIMITATIONS (regression-tested in tests/lib.nix source-parse set):
  #   - Positions come from builtins.unsafeGetAttrPos, an explicitly
  #     UNSTABLE builtin. Under pure/restricted eval readFile is gated
  #     (pathExists + tryEval) so this degrades to null, not a throw.
  #   - The matcher is textual and best-effort: it keys off the FIRST
  #     `mkIf` token at/after the position, so a literal `mkIf` in a
  #     comment or string before the real guard will mislead it. This
  #     fragility is why provenance is opt-in (--full) and why native
  #     module-system provenance (RFC #2) is the durable fix.
  extractMkIfCondition =
    {
      file,
      line,
      column,
    }:
    if file == null || line == null || column == null then
      null
    else
      let
        content = tryReadFile file;
      in
      if content == null then
        null
      else
        let
          offset = computeOffset content line column;
          rest = builtins.substring offset (-1) content;
          splits = builtins.split "mkIf[[:space:]]+" rest;
          afterMkIf = if builtins.length splits >= 3 then builtins.elemAt splits 2 else null;
        in
        if afterMkIf == null then null else extractPrimary (skipWS afterMkIf);
}
