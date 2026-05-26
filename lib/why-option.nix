{ lib, internal }:
let
  splitPath = path: lib.splitString "." path;
in
{
  # resolve :: { modules, specialArgs ? {}, config, options, path } -> AST
  #
  # Returns a structured introspection AST for a single option path.
  # The AST is the stable JSON contract documented in
  # docs/reference/json-schema.md (planned).
  #
  # Full composition lives in commit 8; for now this delegates to the
  # options-surface pass only.
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
      surfaceResult = internal.fromOptions { inherit options pathParts; };
    in
    surfaceResult;

  # render :: { ast, format ? "tree", maxValue ? 200, noColor ? false } -> string
  #
  # Renders an introspection AST to a human-readable string. Implemented
  # in commits 15-17 (CLI-side renderer); this Nix-side function is a
  # stub used by tests that need a quick textual representation.
  render =
    {
      ast,
      format ? "tree",
      maxValue ? 200,
      noColor ? false,
    }:
    "nix-why: render not yet implemented (format=${format}); use --json and pipe through the CLI renderer";
}
