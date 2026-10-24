{
  description = "WeChat DevTools (微信开发者工具) for Linux, built from the official Windows installer";

  inputs = {
    # 固定 nixpkgs：官方 DevTools 依赖 Electron 36.6.0 与 nodejs 22，
    # unstable 的 electron 已经是 43.x，ABI 不兼容。
    # 这里 pin 到 2025-06-30 的 nixos-24.11 branch head，
    # 它同时提供 electron_36 系列与 nodejs_22，且 asar 3.2.4 与官方打包工具一致。
    nixpkgs.url = "github:NixOS/nixpkgs/50ab793786d9de88ee30ec4e4c24fb4236fc2674";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      perSystem = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          # 所有外部产物的 url + sha256，单一来源。
          sources = import ./packages/sources.nix;

          # 原生模块构建器（对着 Electron 36.6.0 头文件）。
          nativeModules = pkgs.callPackage ./packages/native-modules.nix {
            electronHeaders = pkgs.fetchurl {
              url = sources.electronHeaders.url;
              sha256 = sources.electronHeaders.sha256;
            };
          };

          # 对官方 asar 的所有改动，声明式列表。
          asarPatches = import ./packages/patches.nix {
            patchDir = ./patches;
          };

          package = pkgs.callPackage ./packages/default.nix {
            inherit sources asarPatches nativeModules;
          };
        in
        {
          packages.default = package;
          packages.wechat-devtools = package;

          checks.statix = pkgs.runCommandLocal "statix-check" {
            src = ./.;
            nativeBuildInputs = [ pkgs.statix ];
          } ''
            statix check ${./.} --config ${./.}/.statix.toml
            touch $out
          '';
        });

      nixosModule = { config, pkgs, ... }: {
        imports = [ ./modules/default.nix ];
      };
    in
    perSystem // {
      nixosModules.default = nixosModule;
    };
}
