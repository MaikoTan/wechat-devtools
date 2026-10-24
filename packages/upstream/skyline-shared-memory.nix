# skyline-shared-memory：Skyline 的共享内存模块（CMake + spdlog）。
#
# 官方 asar 里 node_modules/sharedMemory 只带 win32 变体，
# 以前用 msojocs/skyline-shared-memory 的预编译 Linux 产物，现在从源码构建。
#
# 两个坑：
#   1. 官方 CMakeLists 依赖 vcpkg 装 spdlog + pnpm/cmake-js，
#      在 Nix sandbox 里跑不通，用干净版 CMakeLists 代替。
#   2. nixpkgs 的 libspdlog.so 用新版 gcc 编译，需要 CXXABI_1.3.15，
#      而 Electron 内置的 libstdc++ 是 gcc 13（最高 CXXABI_1.3.9）。
#      所以 spdlog 必须用 stdenv.cc 自己编一份，不能用 nixpkgs 的。
{ lib, stdenv, fetchgit, fetchurl, cmake, python3, pkg-config
, gnutar, nodeAddonApi, electronHeaders }:

let
  src = fetchgit {
    url = "https://github.com/msojocs/skyline-shared-memory.git";
    rev = "7e9698f7395e97c73d0f6708c7c769e3489e87aa";
    hash = "sha256-V0LaQmMBNnoXQIdhfyP/YaGQbpCa2LJR06eDpEA2TBw=";
    fetchSubmodules = false;
  };

  # 自己编的 spdlog：跟着 stdenv.cc（gcc 13）走，ABI 与 Electron 一致。
  # nixpkgs 的 spdlog 用新版 gcc，链进去会在 Electron 进程里加载失败。
  spdlogSelf = stdenv.mkDerivation {
    pname = "spdlog";
    version = "1.17.0";
    src = fetchurl {
      url = "https://github.com/gabime/spdlog/archive/refs/tags/v1.17.0.tar.gz";
      sha256 = "2IYpVcbXTlhGs/WAsWBdJCixHZekENhuL7E+hXzTp0Q=";
    };
    nativeBuildInputs = [ cmake ];
    cmakeFlags = [
      "-DSPDLOG_BUILD_SHARED=OFF"
      "-DSPDLOG_BUILD_EXAMPLE=OFF"
      "-DSPDLOG_BUILD_BENCH=OFF"
      "-DSPDLOG_BUILD_TESTS=OFF"
      "-DSPDLOG_FMT_EXTERNAL=OFF"
    ];
    # 只装库与头文件。stdenv 的 cmake 在源码子目录下建 build/，
    # libspdlog.a 在 build/ 里，include/ 在源码根。
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib $out/include
      cp -r ../include/spdlog $out/include/
      cp libspdlog.a $out/lib/
      runHook postInstall
    '';
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

  cleanCMakeLists = ./skyline-shared-memory-CMakeLists.txt;
in
stdenv.mkDerivation {
  pname = "skyline-shared-memory";
  version = "1.1.0";
  inherit src;

  nativeBuildInputs = [ cmake python3 pkg-config ];

  NODE_ADDON_API_DIR = nodeAddonApiDir;
  NODE_API_HEADERS_DIR = "${electronHeadersDir}/include/node";
  SPDLOG_DIR = spdlogSelf;

  # stdenv 的 configurePhase 会用原始 CMakeLists 跑 cmake（依赖 vcpkg 的 spdlog），
  # 必须禁用它，改在 buildPhase 里用干净版 CMakeLists 手动配置。
  cmakeConfigurePhase = "";
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cp ${cleanCMakeLists} CMakeLists.txt

    cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DNODE_ADDON_API_DIR=$NODE_ADDON_API_DIR \
      -DNODE_API_HEADERS_DIR=$NODE_API_HEADERS_DIR \
      -DSPDLOG_DIR=$SPDLOG_DIR

    cmake --build build -j$NIX_BUILD_CORES

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    install -m755 build/sharedMemory.node $out/sharedMemory.node
    runHook postInstall
  '';

  meta = {
    description = "Skyline shared memory module for WeChat DevTools (self-built)";
    platforms = lib.platforms.linux;
  };
}
