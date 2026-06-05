# Source sample (#6): guard is a bare dotted attribute path.
{
  config.x = lib.mkIf config.feature.enabled 1;
}
