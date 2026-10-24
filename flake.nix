{
  description = "WeChat DevTools (微信开发者工具) for Linux, built from the official Windows installer";

  inputs = {
    # 运行期依赖：Electron 的 GUI/系统库（gtk/mesa/llvm/glibc/xorg/...）。
    # 默认与 nixpkgsBuild 同一个 pin；用户可以 follows 到自己系统的
    # nixpkgs，让这 ~1G 的闭包与系统共享，见 docs/pinning.md 的
    # 「共享运行时库」。命名成 nixpkgs 是为了贴合大家写
    # inputs.<name>.inputs.nixpkgs.follows = "nixpkgs" 的习惯。
    nixpkgs.url = "github:NixOS/nixpkgs/50ab793786d9de88ee30ec4e4c24fb4236fc2674";

    # 构建期依赖：官方 DevTools 依赖 Electron 36.6.0 与 nodejs 22，
    # unstable 的 electron 已经是 43.x，ABI 不兼容。
    # 这里 pin 到 2025-06-30 的 nixos-24.11 branch head，
    # 它同时提供 electron_36 系列与 nodejs_22，且 asar 3.2.4 与官方打包工具一致。
    # 构建工具（gcc 13 / asar / nodejs / rust）必须来自这里，不跟随用户的
    # nixpkgs，否则在较新的系统上会用新版 gcc 编译，原生模块要求的
    # GLIBCXX 符号超出 Electron 内置 libstdc++ 的范围，加载即失败。
    nixpkgsBuild.url = "github:NixOS/nixpkgs/50ab793786d9de88ee30ec4e4c24fb4236fc2674";

    flake-utils.url = "github:numtide/flake-utils";
    # pinned nixpkgs 的 rustc 是 1.82，而 skyline-native 需要 1.85。
    # 用 fenix 拿一份新版工具链，只用于自建原生模块。
    fenix.url = "github:nix-community/fenix";
  };

  outputs = { self, nixpkgs, nixpkgsBuild, flake-utils, fenix }:
    let
      # 所有外部产物的 url + sha256，单一来源。perSystem 与 nixosModule 共用。
      sources = import ./packages/sources.nix;

      perSystem = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgsBuild {
            inherit system;
            config.allowUnfree = true;
          };

          # 运行时库：默认同一个 pin，用户可 follows 到自己的 nixpkgs。
          pkgsRuntime = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };


          # Electron 36.6.0 头文件：原生模块编译用。
          electronHeaders = pkgs.fetchurl {
            url = sources.electronHeaders.url;
            sha256 = sources.electronHeaders.sha256;
          };

          # node-addon-api 的 napi.h：自建 Node-API 模块用。
          nodeAddonApi = pkgs.fetchurl {
            url = "https://registry.npmjs.org/node-addon-api/-/node-addon-api-8.3.1.tgz";
            sha256 = "fKCqetjgf4E00bC12Gd83VzyxN7VyOA18ze56Kl7veY=";
          };

          # Rust 工具链：pinned nixpkgs 只有 1.82，skyline-native 要 1.85+。
          rustToolchain = fenix.packages.${system}.fromToolchainFile {
            file = ./rust-toolchain.toml;
            inherit (sources.rustToolchain) sha256;
          };
          rustPlatform = pkgs.makeRustPlatform {
            rustc = rustToolchain;
            cargo = rustToolchain;
          };

          # 原生模块构建器（对着 Electron 36.6.0 头文件）。
          nativeModules = pkgs.callPackage ./packages/native-modules.nix {
            inherit electronHeaders;
          };

          # 对官方 asar 的所有改动，声明式列表。
          asarPatches = import ./packages/patches.nix {
            patchDir = ./patches;
          };

          package = pkgs.callPackage ./packages/default.nix {
            inherit sources asarPatches nativeModules
              electronHeaders nodeAddonApi rustPlatform;
            runtimePkgs = pkgsRuntime;
          };
        in
        {
          packages.default = package;
          packages.wechat-devtools = package;

          checks.statix = pkgs.runCommandLocal "statix-check" {
            src = ./.;
            nativeBuildInputs = [ pkgs.statix ];
          } ''
            statix check -c ${./.} ${./.}
            touch $out
          '';

          # 原生模块装载冒烟测试。CLI 的 --help 不会碰 .node，
          # ABI 回归（缺 GLIBCXX 符号、模块版本不匹配）只有真加载才发现。
          # 用 pin 里的 nodejs_22，与 Electron 36 内置的 Node 大版本一致。
          checks.native-modules = pkgs.runCommandLocal "native-modules-check" {
            nativeBuildInputs = [ pkgs.nodejs ];
          } ''
            node ${./packages/smoke-test.mjs} \
              ${package}/electron/resources/app.asar.unpacked
            touch $out
          '';
        });

      # NixOS 模块。构建工具（gcc 13 / asar / nodejs / rust）必须用
      # nixpkgsBuild，否则在较新的系统上会用新版 gcc 编译，原生模块
      # 要求的 GLIBCXX 符号超出 Electron 内置 libstdc++ 的范围，加载即失败。
      # 运行时库仍用系统的 pkgs，闭包才能与系统共享。
      nixosModule = { config, pkgs, lib, ... }:
        let
          system = pkgs.system;
          buildPkgs = import nixpkgsBuild {
            inherit system;
            config.allowUnfree = true;
          };
          rustToolchain = fenix.packages.${system}.fromToolchainFile {
            file = ./rust-toolchain.toml;
            inherit (sources.rustToolchain) sha256;
          };
        in
        {
          imports = [ ./modules/default.nix ];
          _module.args.wechatDevtoolsBuildPkgs = buildPkgs;
          _module.args.wechatDevtoolsRustPlatform = buildPkgs.makeRustPlatform {
            rustc = rustToolchain;
            cargo = rustToolchain;
          };
        };
    in
    perSystem // {
      nixosModules.default = nixosModule;
    };
}
