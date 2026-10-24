# 官方 app.asar 里随 Windows 包发布的原生模块，在 Linux 上必须重新编译。
# 全部对着 Electron 36.6.0 的头文件 + N-API/Node ABI 135 构建，
# 产物直接覆盖 app.asar.unpacked/node_modules 下的同名 .node。
#
# 为什么不用 nixpkgs 的 electron 头文件：
#   nixpkgs unstable 的 electron 已经是 43.x，与官方要求的 36.6.0 不符，
#   ABI 不一致会导致加载时 "was compiled against a different Node.js version"。
#   因此头文件由 sources.nix 的 electronHeaders 固定提供。
#
# node-gyp 的配置方式：
#   node-gyp 只认 npm_config_* 前缀的环境变量（见其 lib/node-gyp.js），
#   并把下划线换成连字符后当作命令行选项。所以：
#     npm_config_nodedir   -> --nodedir    （头文件目录）
#     npm_config_target    -> --target     （目标版本）
#     npm_config_dist_url  -> --dist-url   （头文件下载源，用于生成 config.gypi）
#     npm_config_runtime   -> --runtime    （electron）
#   注意不能只设 npm_package_config_node_gyp_nodedir —— 那是 npm 内部的
#   命名空间，直接调用 node-gyp 时不生效。
{ lib, stdenv, nodejs, python3, pkg-config, openssl, electronHeaders, xorg }:

let
  # node-gyp 需要知道「目标运行时」是 Electron 而不是 Node。
  gypEnv = {
    npm_config_target = "36.6.0";
    npm_config_dist_url = "https://electronjs.org/headers";
    npm_config_runtime = "electron";
    npm_config_arch = "x64";
  };

  # npm 自带的 node-gyp 入口（nixpkgs 的 nodejs 里只有 node/npm/npx/corepack，
  # 没有独立的 node-gyp 可执行文件）。
  nodeGyp = "${nodejs}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js";

  # 把一个 npm tarball 解成 node_modules/<name> 目录。
  # npm tarball 内部统一是 package/ 顶层目录，先解到临时目录再整体搬过去，
  # 这样带 scope 的名字（@vscode/spdlog）也能正确处理。
  unpackNpm = name: src: ''
    mkdir -p "node_modules/$(dirname ${name})"
    tmp=$(mktemp -d)
    tar -xzf ${src} -C "$tmp" --strip-components=1
    rm -rf "node_modules/${name}"
    mv "$tmp" "node_modules/${name}"
  '';

  # 通用构建器。
  #   src    —— 模块自身的 npm tarball
  #   deps   —— { "dep-name" = <tarball>; }，会摆成 node_modules/<dep-name>
  #   binary —— 产物在 build/Release/ 下的文件名
  buildNativeModule =
    {
      pname,
      version,
      src,
      deps ? { },
      binary,
      # nodegit 需要链接系统 OpenSSL，其余模块不需要。
      # 传的是「同时含 include/ 与 lib/ 的根目录」：
      #   · binding.gyp 用它做 include_dirs 与链接库路径
      #   · vendor/libssh2/configure 用 --with-libssl-prefix=<它> 找 openssl
      # nixpkgs 把 openssl 的头文件（openssl.dev）和库（openssl）拆成两个输出，
      # 所以这里在构建目录里拼一个统一视图。
      opensslDir ? null,
      extraEnv ? { },
      buildInputs ? [ ],
    }:
    stdenv.mkDerivation {
      inherit pname version src;

      nativeBuildInputs = [ nodejs python3 pkg-config ];

      # native-keymap 需要 X11 头文件与库（binding.gyp 里用 pkg-config 找 x11/xkbfile）。
      # openssl 进 buildInputs 是为了让 autoPatchelfHook 把 libssl/libcrypto
      # 写进 RPATH —— nodegit 链接了它们，运行时必须找得到。
      buildInputs = buildInputs ++ [ xorg.libX11 xorg.libxkbfile ]
        ++ lib.optional (opensslDir != null) openssl.out;

      # npm tarball 解出来就是 package/ 一个目录，直接当 sourceRoot。
      sourceRoot = "package";

      buildPhase = ''
        runHook preBuild

        # ── 解开 Electron 头文件 ──────────────────────────────────
        # node-gyp 的 --nodedir 要指向「包含 include/node/ 的那一层」。
        # electron 的 headers tarball 解压后是 node-v36.6.0/include/node/...
        mkdir -p electron-headers
        tar -xzf ${electronHeaders} -C electron-headers --strip-components=1
        export npm_config_nodedir="$PWD/electron-headers"

        # node-gyp 的缓存目录必须可写
        export npm_config_devdir="$PWD/.node-gyp-cache"

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: ''
          export ${name}="${value}"
        '') (gypEnv // extraEnv))}

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList unpackNpm deps)}

        # ── 拼出统一的 OpenSSL 根目录 ─────────────────────────────
        # nodegit 的 vendor/libssh2/configure 硬编码用 vendor/openssl 作为
        # --with-libssl-prefix，而设置 npm_config_openssl_dir 后
        # acquireOpenSSL 目标会被跳过（不下载 openssl 到 vendor/openssl），
        # 于是 configure 找不到头文件。这里把系统 openssl 软链过去。
        if [ -n "${lib.optionalString (opensslDir != null) "yes"}" ]; then
          mkdir -p openssl-root
          ln -s ${openssl.dev}/include openssl-root/include
          ln -s ${openssl.out}/lib openssl-root/lib
          export npm_config_openssl_dir="$PWD/openssl-root"
          rm -rf vendor/openssl
          ln -s "$PWD/openssl-root" vendor/openssl
        fi

        # nodegit 的测试会在构建期跑，跳过。
        export NODEGIT_SKIP_TESTS=1

        node ${nodeGyp} rebuild

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp build/Release/${binary} $out/
        runHook postInstall
      '';
    };
in
{ inherit buildNativeModule unpackNpm nodeGyp gypEnv; }
