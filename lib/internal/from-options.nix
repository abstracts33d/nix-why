{ lib }:
{
  # fromOptions :: { options, pathParts } -> AST
  #
  # Reads the publicly documented `options.<path>.*` attributes of an
  # evaluated NixOS-style option and returns a structured introspection
  # AST. This is the "safe path" of the hybrid evaluation strategy: only
  # public option-type attributes are read, no internal coupling.
  # Implemented in commit 5.
  fromOptions =
    {
      options,
      pathParts,
    }:
    {
      path = lib.concatStringsSep "." pathParts;
      type = "unknown";
      value = null;
      isDefined = false;
      winningPriority = null;
      declarations = [ ];
      definitions = [ ];
    };
}
