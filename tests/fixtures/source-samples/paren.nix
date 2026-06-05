# Source sample (#6): parenthesised boolean condition guard.
# Read as text by the source extractor; not evaluated.
{
  config.services.demo.enable = lib.mkIf (config.foo && config.bar) true;
}
