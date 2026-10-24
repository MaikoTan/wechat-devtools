{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.wechat-devtools;

  # 模块被 NixOS 配置 import 时，flake 的 inputs 已经就位，
  # 但模块本身拿不到 self，所以这里按 flake 的同一套 callPackage 组装。
  # 注意：nixpkgs 由 flake 固定，模块里用系统的 pkgs 会绕过 pin，
  # 因此 electron 头文件等也统一从 flake 的 nixpkgs 取。
  sources = import ../packages/sources.nix;

  nativeModules = pkgs.callPackage ../packages/native-modules.nix {
    electronHeaders = pkgs.fetchurl {
      url = sources.electronHeaders.url;
      sha256 = sources.electronHeaders.sha256;
    };
  };

  asarPatches = import ../packages/patches.nix {
    patchDir = ../patches;
  };

  wechatDevToolsPackage = pkgs.callPackage ../packages/default.nix {
    inherit sources asarPatches nativeModules;
  };
in
{
  options.services.wechat-devtools = {
    enable = mkEnableOption "WeChat DevTools (微信开发者工具)";

    enableDesktopItem = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to install the .desktop file and icon for desktop integration.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ wechatDevToolsPackage ];
  };
}
