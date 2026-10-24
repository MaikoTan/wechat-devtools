# 升级指南

## 换 DevTools 版本

### 1. 更新 sources.nix

```nix
installer = {
  version = "2.02.2608080";   # ← 改这里
  url = "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/release/<hash>/wechat_devtools_<version>_win32_x64.exe";
  sha256 = "...";             # ← 和这里
};
```

`version` 同时出现在 url 与 version 字段，两处都要改。

计算 sha256：

```bash
nix hash file --sri --type sha256 wechat_devtools_<version>_win32_x64.exe
# 或
nix-prefetch-url <url>
```

### 2. 核对补丁目标字符串

`packages/patches.nix` 里每条 `replace` 的 `from` 都是官方代码里的字面量，
版本升级后可能漂移。逐条在新版 asar 里搜：

```bash
# 解出新版 asar
7z x -o7zout wechat_devtools_<version>_win32_x64.exe
asar extract 7zout/resources/app.asar app

# 核对
grep -c "options.platform === 'darwin'" \
  app/wechatide-skill/skills/installer/scripts/ensure-cli-path.mjs
grep -c "for(let n=2;n<e.length;n+=1)" \
  app/js/common/cli/skill-index.js
```

`prepend`/`append` 的补丁不依赖目标内容，一般不受影响，
但要确认目标文件仍然存在。

### 3. 核对原生模块版本

```bash
for m in extract-file-icon native-keymap native-watchdog node-pty \
         @vscode/spdlog @vscode/sqlite3 nodegit; do
  node -e "console.log('$m', require('./app/node_modules/$m/package.json').version)"
done
```

版本变了就要同步改 `packages/sources.nix` 的 `npm` 条目
（url + sha256）和 `packages/default.nix` 里对应的 `version` 字段。

### 4. 核对 Electron 版本

```bash
grep -o "electron-[0-9.]*" app/js/fee5fd3fed2aeb1189f1b895fb0b171e.js
```

如果官方升到 37.x，需要同步改：

- `packages/default.nix` 的 `electronZip` url
- `packages/native-modules.nix` 的 `npm_config_target`
- `packages/sources.nix` 的 `electronHeaders`
- `packages/default.nix` 里 7 个 `nativeAddon` 的 `version`

### 5. 核对 unpack glob

```bash
find 7zout/resources/app.asar.unpacked -type f \
  | sed 's|.*app.asar.unpacked/||' | sort > official.txt

nix build .#wechat-devtools --no-link
O=$(nix path-info .#wechat-devtools 2>/dev/null || readlink -f result)
find $O/electron/resources/app.asar.unpacked -type f \
  | sed "s|$O/electron/resources/app.asar.unpacked/||" | sort > built.txt

diff official.txt built.txt
```

差异应该**只有**我们刻意删掉的 Windows/macOS 文件。
如果出现新的未覆盖路径，往 `unpackGlob` 里加模式。

### 6. 核对删除清单

```bash
# 官方新增的 Windows 专有目录/文件
find app -name "*.dll" -o -name "*.exe" -o -name "*.lib" -o -name "*.pdb" \
  -o -name "fsevents.node" -o -name "conpty*.node"
```

### 7. 构建与验证

```bash
nix flake check
nix build .#wechat-devtools --no-link

# 三个入口
$O/bin/wechat-devtools-cli --help
$O/bin/wechatide -h

# 原生模块
ELECTRON_RUN_AS_NODE=1 $O/electron/electron /tmp/nativetest.js \
  $O/electron/resources/app.asar.unpacked

# 路径对齐
$O/bin/wechat-devtools-cli islogin --debug 2>&1 | grep -E "installPath|userDirPath"
node -e "console.log(require('crypto').createHash('md5').update('$O/electron/resources/app.asar').digest('hex'))"
```

## 换 nixpkgs pin

`flake.nix` 里：

```nix
nixpkgs.url = "github:NixOS/nixpkgs/50ab793786d9de88ee30ec4e4c24fb4236fc2674";
```

换 pin 时核对：

1. `electron_36` 是否还存在（不存在就得继续 pin）
2. `asar` 的 glob 行为是否变化（`matchBase` 语义）
3. `nodejs` 内置的 node-gyp 版本（影响 `npm_config_*` 解析）
4. `autoPatchelfHook` 的依赖列表是否要跟着 nixpkgs electron 更新
5. `openssl.dev` / `openssl.out` 的输出划分是否变化

详见 [pinning.md](pinning.md)。

## 换预编译二进制

`packages/sources.nix` 的 `swc` / `ripgrep` / `wcc` / `wcsc` /
`wccModule` / `wcscModule` / `skylineClient` / `skylineSharedMemory` /
`floatPigment` 目前来自第三方 release。

换版本时注意：

- swc 的版本要匹配官方 asar 里 `@swc/core` 的版本
- ripgrep 的版本要匹配官方 asar 里 `@vscode/ripgrep` 的版本
  （其 `lib/postinstall.js` 里的 `VERSION` 常量）
- wcc/wcsc 要匹配官方 `node_modules/wcc-electron` 的行为
- 文件名规则不能改：wcc/wcsc 保留 `.exe`，ripgrep 无后缀
