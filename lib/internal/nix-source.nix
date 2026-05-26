{ lib }:
{
  # extractMkIfCondition :: { file, line, column } -> string | null
  #
  # Best-effort: read the source file at the given position and
  # forward-scan for an `mkIf` token, then bracket-balance the condition
  # expression and return it as a string. Returns null on parse failure;
  # the rest of the output remains valid. Implemented in commit 7.
  extractMkIfCondition =
    {
      file,
      line,
      column,
    }:
    null;
}
