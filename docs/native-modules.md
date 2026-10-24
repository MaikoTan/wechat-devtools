# 原生模块

## 重新编译的 7 个模块

官方 app.asar 里随 Windows 包发布的原生模块，在 Linux 上必须重新编译。
全部对着 Electron 36.6.0 头文件 + Node ABI 135 构建，
产物直接覆盖 `app.asar.unpacked/node_modules` 下的同名 `.node`。

| 模块 | 版本 | 产物 | 额外依赖 |
| --- | --- | --- | --- |
| extract-file-icon | 0.3.2 | `addon.node` | node-addon-api@1.7.1 |
| native-keymap | 3.3.2 | `keymapping.node` | — |
| native-watchdog | 1.3.0 | `watchdog.node` | — |
| node-pty | 0.11.0-beta32 | `pty.node` | nan@2.23.1 |
| @vscode/spdlog | 0.13.11 | `spdlog.node` | nan、bindings、mkdirp |
| @vscode/sqlite3 | 5.1.4-vscode | `vscode-sqlite3.node` | node-addon-api@4.3.0、tar 链 |
| nodegit | 0.28.0-alpha.36 | `nodegit.node` | @axosoft/nan、fs-extra 链 |

依赖 tarball 全部来自 `packages/sources.nix` 的 `npm`，版本与官方 asar 内一致。

### node-gyp 配置

node-gyp 只认 `npm_config_*` 前缀的环境变量（见其 `lib/node-gyp.js`），
并把下划线换成连字符后当作命令行选项：

| 环境变量 | 等价选项 | 作用 |
| --- | --- | --- |
| `npm_config_nodedir` | `--nodedir` | 头文件目录 |
| `npm_config_target` | `--target` | 目标版本 36.6.0 |
| `npm_config_dist_url` | `--dist-url` | 头文件下载源 |
| `npm_config_runtime` | `--runtime` | electron |

> 注意不能只设 `npm_package_config_node_gyp_nodedir` —— 那是 npm 内部的
> 命名空间，直接调用 `node-gyp` 时不生效。

node-gyp 入口用 npm 自带的（nixpkgs 的 nodejs 里没有独立的 `node-gyp` 可执行文件）：

```bash
node ${nodejs}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js rebuild
```

### 各模块的额外需求

- **python3** —— node-gyp 需要
- **pkg-config + xorg.libX11 + xorg.libxkbfile** —— native-keymap 的
  binding.gyp 用 `pkg-config x11 xkbfile --libs`
- **tar 链**（tar、chownr、fs-minipass、minipass、minizlib、mkdirp、yallist）
  —— @vscode/sqlite3 的 `deps/extract.js` 用它解压 sqlite 源码
- **krb5 + inetutils** —— nodegit 的 libgit2 需要 `krb5-config` 找 GSSAPI，
  libssh2 的 configure 脚本会调 `hostname`
- **openssl** —— nodegit 链接 libssl/libcrypto

### nodegit 的 OpenSSL

nixpkgs 把 openssl 拆成多个输出（`openssl.dev` 是头文件，`openssl.out` 是库），
而 nodegit 的 `vendor/libssh2/configure` 硬编码用 `vendor/openssl` 作为
`--with-libssl-prefix`。所以在构建目录里拼一个统一视图：

```bash
mkdir -p openssl-root
ln -s ${openssl.dev}/include openssl-root/include
ln -s ${openssl.out}/lib    openssl-root/lib
export npm_config_openssl_dir="$PWD/openssl-root"
rm -rf vendor/openssl
ln -s "$PWD/openssl-root" vendor/openssl
```

设了 `npm_config_openssl_dir` 后 `acquireOpenSSL` 目标会被跳过
（不联网下载 openssl），所以必须手动补上 `vendor/openssl` 软链。

openssl 还要进 `buildInputs`，让 `autoPatchelfHook` 把 libssl/libcrypto
写进 RPATH，否则运行时报 `libcrypto.so.3: cannot open shared object file`。

## 原生模块的来源

官方 asar 里这些模块只带 win32 变体，Linux 下必须自己准备。
分两类：**自建**（从源码编译）和 **上游预编译**（官方/npm 发的 Linux 二进制）。

### 自建的模块

以前用 msojocs 仓库的预编译产物，现在全部从源码自己构建，
derivation 在 `packages/upstream/` 下，每个模块一个文件。

| 模块 | 目标路径 | 源码 |
| --- | --- | --- |
| wcc | `node_modules/wcc-exec/wcc.exe` | msojocs/wx-compiler |
| wcsc | `node_modules/wcc-exec/wcsc.exe` | 同上 |
| wcc 模块 | `node_modules/wcc-electron/build/Release/wcc.node` | 同上 |
| wcsc 模块 | `node_modules/wcc-electron/build/Release/wcsc.node` | 同上 |
| skyline client | `node_modules/skyline-addon/build/skyline.node` | msojocs/skyline-client-server |
| sharedMemory | `node_modules/sharedMemory/sharedMemory.node` | msojocs/skyline-shared-memory |
| float-pigment | `node_modules/node-float-pigment-css/float-pigment-css-for-nodejs.node` | msojocs/float-pigment-rust |

四个仓库的构建系统：

- **wx-compiler**：CMake + C++11。官方 `src/module/CMakeLists.txt` 依赖
  `pnpm` + `cmake-js`（`execute_process` 调 pnpm），sandbox 里跑不通，
  用干净版 `wx-compiler-CMakeLists.txt` 代替，源码文件列表与官方一致。
  需要 node-addon-api 的 `napi.h` 和 Electron 的 `node_api.h`。
- **float-pigment-rust**：napi-rs，`cargo build --release` 出
  `libnapi_float_pigment.so`，重命名为 `float-pigment-css-for-nodejs.node`。
- **skyline-client-server/packages/native**：napi-rs，
  `--no-default-features --features client`，产物重命名为 `skyline.node`。
  crate 在子目录里，`postUnpack` 把它提到源码根，
  否则 `buildRustPackage` 找不到 `Cargo.lock`。
- **skyline-shared-memory**：CMake + vcpkg spdlog + cmake-js，
  同样用干净版 CMakeLists。

#### 两个必须处理的 ABI 坑

**1. spdlog 必须自己编，不能用 nixpkgs 的。**
nixpkgs 的 `libspdlog.so` 用新版 gcc 编译，需要 `CXXABI_1.3.15`，
而 Electron 36.6.0 内置的 libstdc++ 是 gcc 13，最高只到 `CXXABI_1.3.9`。
所以 derivation 内部用 `stdenv.cc`（gcc 13.3.0）编一份
`-DSPDLOG_BUILD_SHARED=OFF` 的 `libspdlog.a`，静态链进模块。
顺带避开了 nixpkgs spdlog 的 `libfmt.so.12` 依赖
（`--whole-archive` 拉不起传递依赖的符号）。

**2. `<iostream>` 会引入 `GLIBCXX_3.4.32`。**
nixpkgs 的 gcc 13 头文件在 `<iostream>` 里声明了
`_ZSt21ios_base_library_initv`，这个符号只在 gcc 15 的 libstdc++ 里提供。
wcc/wcsc 源码多处 `#include <iostream>`，直接编出来在 Electron 里加载失败。
`wx-compiler-iostream-stub.cc` 给一个空实现：
wcc/wcsc 只用 iostream 打日志，不依赖这个初始化函数，
`std::cout`/`std::cerr` 仍正常。加上桩之后 GLIBCXX 需求回落到 3.4.29。

#### Rust 工具链要单独 pin

pinned nixpkgs 的 rustc 是 1.82.0，编不了 skyline-native（要 1.85）
和 float-pigment 的依赖（要 1.88）。用 fenix 的
`rust-toolchain.toml`（channel 1.88.0）现组一个 `rustPlatform`。

上游两个仓库都没提交 `Cargo.lock`（被 `.gitignore`），
用本地 `cargo build` 生成的版本放在 `packages/upstream/` 下，
float-pigment 还要靠 `cargoPatches` 把它补进源码树。

### 上游预编译的模块

这两个是官方/npm 直接发的 Linux 二进制，不是第三方重新打包的：

| 模块 | 目标路径 | 来源 |
| --- | --- | --- |
| swc | `node_modules/@swc/core/swc.linux-x64-gnu.node` | npm `@swc/core-linux-x64-gnu` |
| ripgrep | `node_modules/@vscode/ripgrep/bin/rg` | ripgrep-prebuilt v13.0.0-10 |

### 两个命名坑

**wcc/wcsc 必须保留 `.exe` 后缀。** 官方 `getWXMLParsePath()`：

```js
const h = "darwin" === process.platform
const e = h ? "wcc" : "wcc.exe"
return this.getLazyModuleTargetPath("wcc-exec", e)
```

Linux 走 `wcc.exe` 分支，文件内容是 Linux ELF。
msojocs 的包改成了无后缀的 `wcc`/`wcsc`，那是他的 bug。

**ripgrep 无后缀。** `lib/index.js`：

```js
module.exports.rgPath = path.join(__dirname, `../bin/rg${process.platform === 'win32' ? '.exe' : ''}`)
```

### 两个是 tarball 不是二进制

`@swc/core-linux-x64-gnu` 和 ripgrep-prebuilt 发的都是 `.tgz`/`.tar.gz`，
需要解压取出里面的文件：

```bash
tar -xzf ${swc} -C node_modules/@swc/core --strip-components=1 package/swc.linux-x64-gnu.node
tar -xzf ${ripgrep} -C node_modules/@vscode/ripgrep/bin/ rg
```

### 路径解析

`getLazyModuleTargetPath` 用 `preferUnpackedTargetPath` 把
`app.asar` 路径改写成 `app.asar.unpacked`：

```js
preferUnpackedTargetPath(e) {
  const o = e.replace(/([/\\])app\.asar([/\\]|$)/, "$1app.asar.unpacked$2")
  return o !== e && fs.existsSync(o) ? o : e
}
```

配合 `ELECTRON_BASE_APP_PATH`，最终解析到
`<root>/electron/resources/app.asar.unpacked/node_modules/...`。

## 验证

```bash
cat > /tmp/nativetest.js <<'EOF'
const path = require('path');
const base = process.argv[2];
const mods = [
  ['native-keymap', 'node_modules/native-keymap/build/Release/keymapping.node'],
  ['native-watchdog', 'node_modules/native-watchdog/build/Release/watchdog.node'],
  ['node-pty', 'node_modules/node-pty/build/Release/pty.node'],
  ['@vscode/spdlog', 'node_modules/@vscode/spdlog/build/Release/spdlog.node'],
  ['@vscode/sqlite3', 'node_modules/@vscode/sqlite3/build/Release/vscode-sqlite3.node'],
  ['nodegit', 'node_modules/nodegit/build/Release/nodegit.node'],
  ['wcc-electron', 'node_modules/wcc-electron/build/Release/wcc.node'],
  ['skyline-addon', 'node_modules/skyline-addon/build/skyline.node'],
  ['sharedMemory', 'node_modules/sharedMemory/sharedMemory.node'],
  ['float-pigment', 'node_modules/node-float-pigment-css/float-pigment-css-for-nodejs.node'],
  ['swc', 'node_modules/@swc/core/swc.linux-x64-gnu.node'],
];
for (const [name, rel] of mods) {
  try { require(path.join(base, rel)); console.log('OK   ', name); }
  catch (e) { console.log('FAIL ', name, '-', e.message.split('\n')[0]); }
}
EOF

ELECTRON_RUN_AS_NODE=1 $out/electron/electron /tmp/nativetest.js \
  $out/electron/resources/app.asar.unpacked
```

可执行文件：

```bash
$out/electron/resources/app.asar.unpacked/node_modules/@vscode/ripgrep/bin/rg --version
$out/electron/resources/app.asar.unpacked/node_modules/wcc-exec/wcc.exe --help
$out/electron/resources/app.asar.unpacked/node_modules/wcc-exec/wcsc.exe --help
```

## 已知限制

`extract-file-icon` 编译产出但 Linux 上不会加载。官方 `dist/index.js`：

```js
if (os_1.platform() === "win32" || os_1.platform() === 'darwin') {
    getIcon = require("../build/Release/addon.node").getIcon;
}
```

调用方 `js/e67ba1338643f825ce5989aebcd9f50a.js` 也先判断
`"win32"!==process.platform && "darwin"!==process.platform` 直接返回。
直接 `require('.node')` 会报 "Module did not self-register"，
但实际代码路径不会碰它。保留编译只是为了与官方文件清单一致。
