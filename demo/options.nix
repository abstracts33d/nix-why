{ lib, ... }:
{
  options.services.webapp = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the web application.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "Port the web application listens on.";
    };
    workers = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Worker process count.";
    };
    cluster.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run the web application in cluster mode.";
    };
  };
}
