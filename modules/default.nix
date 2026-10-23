{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.wechat-devtools;

  # Import the package from the flake
  wechatDevToolsPackage = pkgs.callPackage ../../packages/default.nix {
    enableDesktopItem = cfg.enableDesktopItem;
    extraPkgs = _: cfg.extraPkgs;
  };
in
{
  options.services.wechat-devtools = {
    enable = mkEnableOption "WeChat DevTools (unofficial)";

    enableDesktopItem = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to install the .desktop file and icon for desktop integration.";
    };

    extraPkgs = mkOption {
      type = types.listOf types.package;
      default = [ pkgs.nss pkgs.libxshmfence ];
      description = "Extra dependencies for the steam-run wrapper.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ wechatDevToolsPackage ];
  };
}