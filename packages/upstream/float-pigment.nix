# float-pigment：wxss 的 float 布局解析器（Rust napi-rs）。
#
# 官方 asar 里 node_modules/node-float-pigment-css 只带 win32 变体，
# 以前用 msojocs/float-pigment-rust 的预编译 Linux 产物，现在从源码构建。
#
# 产物名由 package.json 的 napi.binaryName 决定：float-pigment.linux-x64-gnu.node
# （cargo 产出的是 libnapi_float_pigment.so，需要重命名）。
{ lib, stdenv, fetchgit, rustPlatform }:

let
  src = fetchgit {
    url = "https://github.com/msojocs/float-pigment-rust.git";
    rev = "2188041e41ddfb20651870acfd9a954303adabc3";
    hash = "sha256-9guzmxH1vAiIPvTGYqgndtQPIp8qpe2lxzSgKj5bvQs=";
    fetchSubmodules = false;
  };
in
rustPlatform.buildRustPackage {
  pname = "float-pigment";
  version = "1.0.0";
  inherit src;

  # 上游仓库没有提交 Cargo.lock（被 .gitignore），用本地 cargo 生成的版本，
  # 通过 cargoPatches 补进源码树。
  cargoLock = {
    lockFile = ./float-pigment-Cargo.lock;
  };
  cargoPatches = [ ./float-pigment-Cargo.lock.patch ];

  buildAndTestSubdir = null;

  buildPhase = ''
    runHook preBuild

    cargo build --release --offline

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out

    # cargo 产出 libnapi_float_pigment.so，napi-rs 期望的文件名是
    # float-pigment.linux-x64-gnu.node（见仓库 index.js 的 require 分支）
    cp target/release/libnapi_float_pigment.so \
      "$out/float-pigment.linux-x64-gnu.node"

    runHook postInstall
  '';

  meta = {
    description = "float-pigment CSS parser for WeChat DevTools (self-built)";
    platforms = lib.platforms.linux;
  };
}
