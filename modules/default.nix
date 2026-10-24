{ config, lib, pkgs, wechatDevtoolsBuildPkgs, wechatDevtoolsRustPlatform, ... }:

with lib;

let
  cfg = config.services.wechat-devtools;

  # 构建工具必须用 flake pin 的 nixpkgs：原生模块对着 Electron 36.6.0
  # 内置的 libstdc++（gcc 13）编译，用系统新版 gcc 会要求更新的 GLIXX
  # 符号，模块在 Electron 进程里加载即失败。
  # 运行时库（gtk/mesa/llvm/...）用系统的 pkgs，闭包才能与系统共享。
  buildPkgs = wechatDevtoolsBuildPkgs;

  sources = import ../packages/sources.nix;

  electronHeaders = buildPkgs.fetchurl {
    url = sources.electronHeaders.url;
    sha256 = sources.electronHeaders.sha256;
  };

  nodeAddonApi = buildPkgs.fetchurl {
    url = "https://registry.npmjs.org/node-addon-api/-/node-addon-api-8.3.1.tgz";
    sha256 = "fKCqetjgf4E00bC12Gd83VzyxN7VyOA18ze56Kl7veY=";
  };

  nativeModules = buildPkgs.callPackage ../packages/native-modules.nix {
    inherit electronHeaders;
  };

  asarPatches = import ../packages/patches.nix {
    patchDir = ../patches;
  };

  wechatDevToolsPackage = buildPkgs.callPackage ../packages/default.nix {
    inherit sources asarPatches nativeModules
      electronHeaders nodeAddonApi;
    rustPlatform = wechatDevtoolsRustPlatform;
    # 运行时库走系统 pkgs，与系统其他 GUI 组件共享闭包
    runtimePkgs = pkgs;
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
