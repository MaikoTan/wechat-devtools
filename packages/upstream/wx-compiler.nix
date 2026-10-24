# wx-compiler：wxml/wxss 编译器（可执行文件 + Node-API 模块）。
#
# 官方 asar 里 node_modules/wcc-exec 与 node_modules/wcc-electron 只带
# win32 变体，以前用 msojocs/wx-compiler 的预编译 Linux 产物，现在从源码构建。
#
# 产出四个文件：
#   wcc / wcsc                    可执行文件（CLI 编译用）
#   wcc.node / wcsc.node          Node-API 模块（进程内编译用）
#
# 为什么不用仓库自带的 CMakeLists：
#   官方 src/module/CMakeLists.txt 依赖 pnpm + cmake-js + node-addon-api
#   的 npm 安装（execute_process 调 pnpm），在 Nix sandbox 里跑不通。
#   这里用一份干净的 CMakeLists，只保留必要的 include 路径与链接选项，
#   源码文件列表与官方一致。
{ lib, stdenv, fetchgit, cmake, python3, pkg-config, gnutar, nodeAddonApi, electronHeaders }:

let
  src = fetchgit {
    url = "https://github.com/msojocs/wx-compiler.git";
    rev = "0db632ad6fae9c8e933fa948be95ae6d5f7b7106";
    hash = "sha256-FzwMy0lQUoelMjtx9JZzpD/oC/9PSJZI1FNzt80mFWI=";
    fetchSubmodules = false;
  };

  # node-addon-api 的 napi.h：nodeAddonApi 是 npm tarball，先解压出 include 目录。
  nodeAddonApiDir = stdenv.mkDerivation {
    name = "node-addon-api";
    src = nodeAddonApi;
    nativeBuildInputs = [ gnutar ];
    installPhase = ''
      mkdir -p $out
      tar -xzf $src -C $out --strip-components=1
    '';
  };

  # electronHeaders 是官方发布的 tar.gz，先解压出 include/node。
  electronHeadersDir = stdenv.mkDerivation {
    name = "electron-headers";
    src = electronHeaders;
    nativeBuildInputs = [ gnutar ];
    installPhase = ''
      mkdir -p $out
      tar -xzf $src -C $out --strip-components=1
    '';
  };

  # 干净的 CMakeLists：去掉 pnpm/cmake-js 依赖，头文件路径由 Nix 注入。
  cleanCMakeLists = ./wx-compiler-CMakeLists.txt;

  # <iostream> 的 GLIBCXX_3.4.32 桩，见 CMakeLists 里的注释。
  iostreamStub = ./wx-compiler-iostream-stub.cc;
in
stdenv.mkDerivation {
  pname = "wx-compiler";
  version = "1.0.0";
  inherit src;

  nativeBuildInputs = [ cmake python3 pkg-config ];

  NODE_ADDON_API_DIR = nodeAddonApiDir;
  NODE_API_HEADERS_DIR = "${electronHeadersDir}/include/node";
  # stdenv 的 configurePhase 会用原始 CMakeLists 跑 cmake（src/module 依赖 pnpm），
  # 必须禁用它，改在 buildPhase 里用干净版 CMakeLists 手动配置。
  cmakeConfigurePhase = "";
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    # 仓库自带的 CMakeLists.txt 依赖 pnpm/cmake-js，换成干净版
    cp ${cleanCMakeLists} CMakeLists.txt
    cp ${iostreamStub} iostream-stub.cc
    sed -i 's|@IOSTREAM_STUB@|iostream-stub.cc|' CMakeLists.txt

    cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DNODE_ADDON_API_DIR=$NODE_ADDON_API_DIR \
      -DNODE_API_HEADERS_DIR=$NODE_API_HEADERS_DIR

    cmake --build build -j$NIX_BUILD_CORES

    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/modules

    install -m755 build/wcc  $out/bin/wcc
    install -m755 build/wcsc $out/bin/wcsc
    install -m755 build/wcc_module.node  $out/modules/wcc.node
    install -m755 build/wcsc_module.node $out/modules/wcsc.node

    runHook postInstall
  '';

  meta = {
    description = "WXML/WXSS compiler for WeChat DevTools (self-built)";
    platforms = lib.platforms.linux;
  };
}
