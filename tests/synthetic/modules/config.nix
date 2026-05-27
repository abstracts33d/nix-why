# User-side configuration for the test target. Each definition is
# crafted to be asserted on by tests/e2e.bats.
{ lib, config, ... }:
{
  # Two modules set this with different priorities; the default-priority
  # one (100) wins over mkDefault (1000).
  config.services.test.enable = lib.mkDefault true;
  config.services.test.port = 9090;
  config.networking.hostName = "synthetic-test";

  # gated.enable stays false, so the mkIf below evaluates to false
  # and gated.target is left as its default. why-not should pick up
  # this filtered-out definition.
  config.gated.target = lib.mkIf config.gated.enable true;
}
