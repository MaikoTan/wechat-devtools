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

## 预编译的 Linux 替代二进制

这些模块官方只发了 win32 变体（或需要额外工具链），
采用社区构建的 Linux 产物，装进 `app.asar.unpacked` 对应位置。

| 模块 | 目标路径 | 来源 |
| --- | --- | --- |
| swc | `node_modules/@swc/core/swc.linux-x64-gnu.node` | npm `@swc/core-linux-x64-gnu` |
| ripgrep | `node_modules/@vscode/ripgrep/bin/rg` | ripgrep-prebuilt v13.0.0-10 |
| wcc | `node_modules/wcc-exec/wcc.exe` | msojocs/wx-compiler |
| wcsc | `node_modules/wcc-exec/wcsc.exe` | msojocs/wx-compiler |
| wcc 模块 | `node_modules/wcc-electron/build/Release/wcc.node` | 同上 |
| wcsc 模块 | `node_modules/wcc-electron/build/Release/wcsc.node` | 同上 |
| skyline client | `node_modules/skyline-addon/build/skyline.node` | msojocs/skyline-client-server |
| sharedMemory | `node_modules/sharedMemory/sharedMemory.node` | msojocs/skyline-shared-memory |
| float-pigment | `node_modules/node-float-pigment-css/float-pigment-css-for-{nodejs,nwjs}.node` | msojocs/float-pigment-rust |

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
