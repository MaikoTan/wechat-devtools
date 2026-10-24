# 从官方 Windows 安装包构建 Linux 版微信开发者工具。
#
# 完整流程（与 msojocs/wechat-web-devtools-linux 的思路一致，但全部在
# nix derivation 内可复刻，不依赖任何预打包 tarball）：
#
#   1. fetchurl 官方 wechat_devtools_<ver>_win32_x64.exe
#   2. 7z 解出 resources/app.asar + app.asar.unpacked
#   3. asar extract 全量解包
#   4. 删除 Windows/macOS 专有文件
#   5. 应用 packages/patches.nix 声明的补丁
#   6. 装入 7 个重新编译的原生模块 + 若干预编译 Linux 替代二进制
#   7. asar pack 重新打包（unpack glob 与官方逐字节对齐）
#   8. 组装 $out：electron 运行时 + resources + 三个启动器 + desktop item
#
# 关键路径契约（已对照官方代码逐行验证）：
#   IDE 侧 app.getAppPath() 与 CLI 侧 ELECTRON_BASE_APP_PATH 必须解析到
#   同一个字符串 <root>/electron/resources/app.asar，
#   否则 md5(installPath) 不同，两边会写不同的数据目录，.ide/.cli 握手失败。
#   因此 $out/electron 必须是真实目录（不是符号链接），
#   且启动器必须显式 export ELECTRON_BASE_APP_PATH。
{ lib, stdenv, fetchurl, p7zip, asar, nodejs, openssl, makeWrapper
, autoPatchelfHook, unzip
, alsa-lib, at-spi2-atk, cairo, cups, dbus, expat, gdk-pixbuf, glib
, gtk3, gtk4, nss, nspr, xorg, pango, systemd, pciutils, libnotify
, pipewire, libsecret, libpulseaudio, speechd-minimal, libdrm, mesa
, libxkbcommon, libxshmfence, libGL, vulkan-loader, krb5, inetutils
, cmake, python3, pkg-config, rustPlatform, fetchgit, gnutar, nodeAddonApi
, electronHeaders, sources, asarPatches, nativeModules }:

let
  # ── 版本号：与 sources.nix 的 installer.version 保持一致 ──────────
  version = sources.installer.version;

  # ── 官方 Windows 安装包 ─────────────────────────────────────────
  installer = fetchurl {
    url = sources.installer.url;
    sha256 = sources.installer.sha256;
  };

  # ── Electron 36.6.0 官方 Linux 运行时 ───────────────────────────
  # 不用 nixpkgs 的 electron：unstable 已是 43.x，与官方要求的 36.6.0 不符，
  # ABI 不一致会导致原生模块加载失败。直接取官方 release zip。
  electronZip = fetchurl {
    url = "https://github.com/electron/electron/releases/download/v36.6.0/electron-v36.6.0-linux-x64.zip";
    sha256 = "ag3ss+OC8y1Ks9uQqr0ILvnuEVT+IFgI+IfiKP2y01U=";
  };

  # 官方 zip 是扁平的（无顶层目录），但 locales/ 是唯一子目录，
  # stdenv 的 sourceRoot 自动检测会误判为多目录，显式指定。
  # autoPatchelfHook 负责把 nixpkgs 的库路径写进 RPATH。
  #
  # 依赖列表与 nixpkgs 官方 electron 包的 binary/generic.nix 保持一致，
  # 这样运行时行为与 nixpkgs 打包的 electron 相同。
  electronUnwrapped = stdenv.mkDerivation {
    pname = "electron-unwrapped";
    inherit version;
    src = electronZip;

    nativeBuildInputs = [ autoPatchelfHook unzip ];
    sourceRoot = ".";

    buildInputs = [
      alsa-lib
      at-spi2-atk
      cairo
      cups
      dbus
      expat
      gdk-pixbuf
      glib
      gtk3
      gtk4
      nss
      nspr
      xorg.libX11
      xorg.libxcb
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      xorg.libxkbfile
      pango
      pciutils
      stdenv.cc.cc
      systemd
      libnotify
      pipewire
      libsecret
      libpulseaudio
      speechd-minimal
      libdrm
      mesa
      libxkbcommon
      libxshmfence
      libGL
      vulkan-loader
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/libexec/electron
      cp -r . $out/libexec/electron/
      chmod +x $out/libexec/electron/electron $out/libexec/electron/chrome-sandbox
      runHook postInstall
    '';
  };

  # ── 7 个需要重新编译的原生模块 ─────────────────────────────────
  # 依赖 tarball 全部来自 sources.nix 的 npm，版本与官方 app.asar 内一致。
  npm = name: fetchurl { url = sources.npm.${name}.url; sha256 = sources.npm.${name}.sha256; };

  nativeAddon = nativeModules.buildNativeModule;

  extractFileIcon = nativeAddon {
    pname = "extract-file-icon";
    version = "0.3.2";
    src = npm "extract-file-icon@0.3.2";
    deps = { "node-addon-api" = npm "node-addon-api@1.7.1"; };
    binary = "addon.node";
  };

  nativeKeymap = nativeAddon {
    pname = "native-keymap";
    version = "3.3.2";
    src = npm "native-keymap@3.3.2";
    binary = "keymapping.node";
  };

  nativeWatchdog = nativeAddon {
    pname = "native-watchdog";
    version = "1.3.0";
    src = npm "native-watchdog@1.3.0";
    binary = "watchdog.node";
  };

  nodePty = nativeAddon {
    pname = "node-pty";
    version = "0.11.0-beta32";
    src = npm "node-pty@0.11.0-beta32";
    deps = { nan = npm "nan@2.23.1"; };
    binary = "pty.node";
  };

  spdlog = nativeAddon {
    pname = "vscode-spdlog";
    version = "0.13.11";
    src = npm "@vscode/spdlog@0.13.11";
    deps = {
      bindings = npm "bindings@1.5.0";
      mkdirp = npm "mkdirp@0.5.5";
      nan = npm "nan@2.23.1";
    };
    binary = "spdlog.node";
  };

  sqlite3 = nativeAddon {
    pname = "vscode-sqlite3";
    version = "5.1.4-vscode";
    src = npm "@vscode/sqlite3@5.1.4-vscode";
    # deps/extract.js 用 tar 解压 sqlite 源码，需要 tar 及其依赖链。
    deps = {
      "node-addon-api" = npm "node-addon-api@4.3.0";
      tar = npm "tar@6.2.1";
      chownr = npm "chownr@2.0.0";
      fs-minipass = npm "fs-minipass@3.0.3";
      minipass = npm "minipass@7.1.2";
      minizlib = npm "minizlib@3.0.2";
      mkdirp = npm "mkdirp@3.0.1";
      yallist = npm "yallist@4.0.0";
    };
    binary = "vscode-sqlite3.node";
  };

  nodegit = nativeAddon {
    pname = "nodegit";
    version = "0.28.0-alpha.36";
    src = npm "nodegit@0.28.0-alpha.36";
    deps = {
      "@axosoft/nan" = npm "@axosoft/nan@2.22.0-gk.1";
      fs-extra = npm "fs-extra@7.0.1";
      graceful-fs = npm "graceful-fs@4.2.11";
      json5 = npm "json5@2.2.3";
      jsonfile = npm "jsonfile@6.1.0";
      universalify = npm "universalify@2.0.0";
    };
    binary = "nodegit.node";
    # nodegit 的 binding.gyp 读 npm_config_openssl_dir 定位系统 OpenSSL，
    # 否则会尝试联网下载并源码编译。
    # libgit2 还需要 krb5-config（binding.gyp 里用它找 GSSAPI），
    # 以及 hostname（libssh2 的 configure 脚本会调用）。
    opensslDir = true;
    buildInputs = [ krb5 inetutils ];
  };

  # ── 预编译的 Linux 替代二进制 ───────────────────────────────────
  # swc 与 ripgrep 官方只发 win32 变体，用上游预编译产物。
  prebuilt = name: fetchurl { url = sources.${name}.url; sha256 = sources.${name}.sha256; };

  swc = prebuilt "swc";
  ripgrep = prebuilt "ripgrep";

  # ── 自建的 Linux 原生模块 ─────────────────────────────────────
  # wcc/wcsc、skyline、float-pigment 以前用 msojocs 的预编译产物，
  # 现在从源码自己构建，不再依赖第三方 release。
  # 各模块的构建方式见 packages/upstream/ 下对应的 derivation。
  wxCompiler = import ./upstream/wx-compiler.nix {
    inherit lib stdenv fetchgit cmake python3 pkg-config gnutar
      nodeAddonApi electronHeaders;
  };
  floatPigment = import ./upstream/float-pigment.nix {
    inherit lib stdenv fetchgit rustPlatform;
  };
  skylineClient = import ./upstream/skyline-client.nix {
    inherit lib fetchgit rustPlatform;
  };
  skylineSharedMemory = import ./upstream/skyline-shared-memory.nix {
    inherit lib stdenv fetchgit fetchurl cmake python3 pkg-config gnutar
      nodeAddonApi electronHeaders;
  };
  # ── 启动器 ─────────────────────────────────────────────────────
  # 三个入口对应官方 Windows 包的 wechat-devtools / wechat-devtools-cli / wechatide。
  # 脚本本体放在 packages/launchers/*.sh，构建时用 substituteAll 替换 @root_dir@。
  launcherNames = [ "wechat-devtools" "wechat-devtools-cli" "wechatide" ];

  # ── asar unpack glob ───────────────────────────────────────────
  # 与官方 app.asar.unpacked 的文件清单逐字节对齐（537 个文件）。
  # 注意：glob 不含 package.json —— asar 的 minimatch 用 matchBase: true，
  # 根级 /package.json 匹配不上任何 **/ 模式，打包后需显式复制。
  # asar 的 --unpack 只接受一个 minimatch pattern，
  # 多个模式要用花括号包起来（{a,b,c}），逗号分隔不会被解析。
  unpackGlob = "{" + lib.concatStringsSep "," [
    "**/bin/**"
    "**/js/unpack/**"
    "**/js/common/fileutils/unpack/**"
    "**/js/common/cli/index.js"
    "**/js/common/cli/skill-error-rules.js"
    "**/js/common/cli/skill-index.js"
    "**/js/common/cli/skill-outcome.js"
    "**/js/common/cloud-functions-debugger-server/worker/node.js"
    "**/js/common/miniprogram-builder/static/scripts/assetsCar/**"
    "**/js/common/miniprogram-builder/static/scripts/checkXcodeEnv"
    "**/js/common/miniprogram-builder/static/scripts/resignIpa"
    "**/wechatide-skill/**"
    "**/*.node"
    "**/*.exe"
    "**/*.dll"
    "**/*.so"
    "**/ios-deploy"
    "**/node_modules/trash/lib/macos-trash"
    "**/node_modules/skyline-addon/**"
    "**/node_modules/wcc-exec/**"
    "**/ripgrep/bin/**"
  ] + "}";

  # ── 补丁应用 ───────────────────────────────────────────────────
  # 每条补丁都是纯文本操作，逐条审计；升级版本时只需重新核对目标字符串。
  applyPatch = p:
    if p.op == "prepend" then ''
      # ${p.note}
      tmp=$(mktemp)
      printf '%s\n' ${lib.escapeShellArg p.content} > "$tmp"
      cat "app/${p.file}" >> "$tmp"
      mv "$tmp" "app/${p.file}"
    ''
    else if p.op == "append" then ''
      # ${p.note}
      printf '%s\n' ${lib.escapeShellArg p.content} >> "app/${p.file}"
    ''
    else if p.op == "replace" then ''
      # ${p.note}
      substituteInPlace "app/${p.file}" \
        --replace ${lib.escapeShellArg p.from} ${lib.escapeShellArg p.to}
    ''
    else throw "unknown patch op: ${p.op}";
in
stdenv.mkDerivation {
  pname = "wechat-devtools";
  inherit version;

  nativeBuildInputs = [ p7zip asar nodejs makeWrapper ];

  src = installer;

  # 官方安装包是 NSIS 打包的 .exe，stdenv 的 unpackPhase 不认识，
  # 改由 buildPhase 里的 7z 处理。
  unpackPhase = ''
    runHook preUnpack
    runHook postUnpack
  '';

  buildPhase = ''
    runHook preBuild

    # ── 1. 7z 解出官方 resources/ ────────────────────────────────
    mkdir -p 7zout
    7z x -y -o7zout ${installer} >/dev/null
    resources=7zout/resources

    # ── 2. asar 全量解包 ─────────────────────────────────────────
    # 官方 asar 是混合结构：既有扁平 hash 文件也有子目录，
    # asar extract-file 在这种包上会崩（符号链接处理），必须整包 extract。
    mkdir -p app
    asar extract "$resources/app.asar" app

    # ── 3. 删除 Windows/macOS 专有文件 ───────────────────────────
    cd app
    rm -rf \
      node_modules/keytar \
      node_modules/spawn-as-admin \
      node_modules/vscode-windows-ca-certs \
      node_modules/vscode-windows-registry \
      node_modules/vscode-windows-registry-node \
      node_modules/windows-process-tree \
      node_modules/@swc/core-win32-x64-msvc \
      node_modules/ios_webkit_debug_proxy \
      bin/adb-win
    # fsevents 是 macOS 的，conpty 是 Windows 的
    find . -name 'fsevents.node' -delete
    find . -name 'conpty*.node' -delete
    # wcc-exec 整个目录删掉重建：官方只带 wcc.exe/wcsc.exe（Windows 二进制），
    # 我们要放的是 Linux ELF，但文件名必须保留 .exe 后缀（见下方说明）。
    rm -rf node_modules/wcc-exec
    find . \( -name '*.lib' -o -name '*.pdb' -o -name '*.dll' \) -delete
    find . -name '*.exe' -delete
    cd ..

    # ── 4. 应用补丁 ──────────────────────────────────────────────
    ${lib.concatMapStrings applyPatch (builtins.attrValues asarPatches)}

    # ── 5. 装入原生模块与预编译二进制 ────────────────────────────
    cd app
    install -D ${extractFileIcon}/addon.node \
      node_modules/extract-file-icon/build/Release/addon.node
    install -D ${nativeKeymap}/keymapping.node \
      node_modules/native-keymap/build/Release/keymapping.node
    install -D ${nativeWatchdog}/watchdog.node \
      node_modules/native-watchdog/build/Release/watchdog.node
    install -D ${nodePty}/pty.node \
      node_modules/node-pty/build/Release/pty.node
    install -D ${spdlog}/spdlog.node \
      node_modules/@vscode/spdlog/build/Release/spdlog.node
    install -D ${sqlite3}/vscode-sqlite3.node \
      node_modules/@vscode/sqlite3/build/Release/vscode-sqlite3.node
    install -D ${nodegit}/nodegit.node \
      node_modules/nodegit/build/Release/nodegit.node

    # swc：官方只带 win32 变体，binding.js 优先找 ./swc.linux-x64-gnu.node。
    # npm 的 @swc/core-linux-x64-gnu 是 tarball，里面才是 .node。
    mkdir -p node_modules/@swc/core
    tar -xzf ${swc} -C node_modules/@swc/core --strip-components=1 package/swc.linux-x64-gnu.node
    chmod +x node_modules/@swc/core/swc.linux-x64-gnu.node

    # ripgrep：rgPath = join(__dirname,'../bin/rg')，无后缀。
    # 上游发的是 tar.gz，里面才是可执行文件。
    mkdir -p node_modules/@vscode/ripgrep/bin
    tar -xzf ${ripgrep} -C node_modules/@vscode/ripgrep/bin/ rg
    chmod +x node_modules/@vscode/ripgrep/bin/rg

    # wcc/wcsc：官方 getWXMLParsePath() 在非 darwin 平台取 "wcc.exe"，
    # 所以必须保留 .exe 后缀（内容是 Linux ELF）。
    mkdir -p node_modules/wcc-exec
    install -m555 ${wxCompiler}/bin/wcc  node_modules/wcc-exec/wcc.exe
    install -m555 ${wxCompiler}/bin/wcsc node_modules/wcc-exec/wcsc.exe
    install -D ${wxCompiler}/modules/wcc.node  node_modules/wcc-electron/build/Release/wcc.node
    install -D ${wxCompiler}/modules/wcsc.node node_modules/wcc-electron/build/Release/wcsc.node

    # Skyline 渲染引擎
    install -D ${skylineClient}/render-client.node \
      node_modules/skyline-addon/build/skyline.node
    install -D ${skylineSharedMemory}/sharedMemory.node \
      node_modules/sharedMemory/sharedMemory.node

    # float-pigment：nodejs 与 nwjs 两个名字都要放
    install -D ${floatPigment}/float-pigment.linux-x64-gnu.node \
      node_modules/node-float-pigment-css/float-pigment-css-for-nodejs.node
    install -D ${floatPigment}/float-pigment.linux-x64-gnu.node \
      node_modules/node-float-pigment-css/float-pigment-css-for-nwjs.node
    cd ..

    # ── 6. asar 重新打包 ─────────────────────────────────────────
    asar pack app app.asar --unpack '${unpackGlob}'
    cp app/package.json app.asar.unpacked/package.json

    # ── 7. 组装 $out ─────────────────────────────────────────────
    mkdir -p $out/bin $out/electron $out/share/applications \
      $out/share/icons/hicolor/scalable/apps

    # electron 运行时：真实目录，这样 process.execPath 的
    # dirname/resources/app.asar 才指向我们的 asar。
    cp -r ${electronUnwrapped}/libexec/electron/. $out/electron/
    chmod +x $out/electron/electron $out/electron/chrome-sandbox

    # resources：我们的 app.asar + unpacked，electron 自带的 default_app.asar 已在
    # （electron 目录来自只读的 nix store，resources 目录权限需要放开才能写入）
    chmod u+w $out/electron/resources
    cp app.asar $out/electron/resources/app.asar
    cp -r app.asar.unpacked $out/electron/resources/

    # 启动器：脚本用 BASH_SOURCE 动态定位 root_dir，无需替换路径。
    # 但 shebang 的 /bin/bash 在 NixOS 上不存在，必须换成 stdenv 的 bash。
    ${lib.concatMapStrings (name: ''
      substitute ${./launchers/${name}.sh} $out/bin/${name} \
        --replace "#!/bin/bash" "#!${stdenv.shell}"
      chmod +x $out/bin/${name}
    '') launcherNames}

    # desktop item
    substituteAll ${./wechat-devtools.desktop} \
      $out/share/applications/wechat-devtools.desktop

    # 图标：官方安装包自带的绿色小程序 logo（vsextensions/agent-audit-vsix 下）
    install -m444 \
      $resources/vsextensions/agent-audit-vsix/resources/mini-program-logo.svg \
      $out/share/icons/hicolor/scalable/apps/wechat-devtools.svg

    runHook postBuild
  '';

  meta = {
    mainProgram = "wechat-devtools";
    platforms = [ "x86_64-linux" ];
    license = with lib.licenses; [ unfree mit ];
    description = "WeChat DevTools (微信开发者工具) built from the official Windows installer";
    homepage = "https://developers.weixin.qq.com/miniprogram/dev/devtools/devtools.html";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
