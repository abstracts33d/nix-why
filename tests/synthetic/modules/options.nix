# Option declarations shared by the test configurations. Designed to
# exercise the variety of cases the CLIs need to handle.
{ lib, ... }:
{
  options.services.test = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the test service.";
    };
    port = lib.mkOption {
      type = lib.types.int;
      default = 8080;
      description = "Listening port.";
    };
    onlyDefault = lib.mkOption {
      type = lib.types.str;
      default = "default-value";
      description = "Never explicitly set; should appear in why-not as only-default.";
    };
  };

  options.networking.hostName = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Hostname.";
  };

  # An option whose only user definition is gated by mkIf.
  options.gated = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Used by mkIf fixture.";
    };
    target = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set by a mkIf-guarded definition; should appear in filteredOutDefinitions.";
    };
  };
}
