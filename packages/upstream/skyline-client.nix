# skyline-client：Skyline 渲染引擎的 Linux 客户端（Rust napi-rs）。
#
# 官方 asar 里 node_modules/skyline-addon 只带 win32 变体，
# 以前用 msojocs/skyline-client-server 的预编译 Linux 产物，现在从源码构建。
#
# 产物名由 packages/native/build.js 的 modules 映射决定：
#   client feature -> render-client.node
# 官方构建命令是
#   cargo build --release --no-default-features --features client
#
# 布局说明：crate 在仓库的 packages/native 下，而 buildRustPackage 要求
# Cargo.lock 位于源码根，所以 postUnpack 把这个子目录提到 sourceRoot。
{ lib, fetchgit, rustPlatform }:

let
  src = fetchgit {
    url = "https://github.com/msojocs/skyline-client-server.git";
    rev = "6611fd29fc21b878dd221fcf8317d056dfee658f";
    hash = "sha256-nCLsr7HTMATbzbuc3B4udwUYrbthMogtlmenMqT+pMg=";
    fetchSubmodules = false;
  };
in
rustPlatform.buildRustPackage {
  pname = "skyline-client";
  version = "2.02.2608070";
  inherit src;

  # 上游仓库没有提交 Cargo.lock（被 .gitignore），用本地 cargo 生成的版本。
  cargoLock = {
    lockFile = ./skyline-client-Cargo.lock;
  };

  # 与官方 build.js 的调用一致（default 也是 client，但显式声明更稳）
  buildNoDefaultFeatures = true;
  buildFeatures = [ "client" ];

  # crate 在 packages/native 下，把它提到源码根，Cargo.lock 才能被找到
  postUnpack = ""
    + "echo 'moving crate to source root'\n"
    + "cp -r $sourceRoot/packages/native/. $sourceRoot/\n"
    + "rm -rf $sourceRoot/packages\n"
    + "";

  buildPhase = ''
    runHook preBuild

    cargo build --release --offline --no-default-features --features client

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out

    # 官方 build.js 把 client feature 的产物命名为 render-client.node
    cp target/release/libskyline_native.so "$out/render-client.node"

    runHook postInstall
  '';

  meta = {
    description = "Skyline render engine Linux client for WeChat DevTools (self-built)";
    platforms = lib.platforms.linux;
  };
}
