# 升级指南

## 查最新版本

官方有一个 JSON API，一条命令就能拿到所有通道的当前版本：

```bash
curl -s https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json \
  | jq -r '.channels[] | "\(.id)\t\(.version)"'
```

输出示例（2026-10-24 查）：

```
stable        2.02.2608080
rc            2.02.2609231
nightly       2.02.2610212
nightly-old   2.01.2602282
```

**只跟 `stable` 通道。** `rc` / `nightly` 是预发布，ABI 与原生模块常有不匹配，
别拿来打包。

拿稳定版的下载地址（url 里的 hash 每次发布都变，必须从 API 取，不能手拼）：

```bash
curl -s https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json \
  | jq -r '.channels[] | select(.id=="stable") | .downloads[]
    | select(.os=="Windows" and .arch=="64") | .url'
```

历史发布记录（含发布日期）在 `history_stable.json`：

```bash
curl -s https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/history_stable.json \
  | jq -r '.history[0:5][] | "\(.version)\t\(.date)"'
```

版本号规则是 `YYMMDD` + 一位序号，例如 `2.02.2608080` 是 2026-08-08 的第 0 个构建，
2026-09-30 发布。

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

**url 里的 `<hash>` 不要手拼**，每次发布都会变，用上面的 API 取：

```bash
curl -s https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json \
  | jq -r '.channels[] | select(.id=="stable") | .downloads[]
    | select(.os=="Windows" and .arch=="64") | .url'
```

算 sha256（二选一）：

```bash
# 下载后本地算
nix hash file --sri --type sha256 wechat_devtools_<version>_win32_x64.exe

# 或让 nix 自己拉（会打印 got: 后面的值）
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

## 换上游预编译二进制

`packages/sources.nix` 里只剩两个上游预编译产物：

| 名称 | 匹配对象 |
| --- | --- |
| `swc` | 官方 asar 里 `@swc/core` 的版本 |
| `ripgrep` | 官方 asar 里 `@vscode/ripgrep` 的版本（其 `lib/postinstall.js` 的 `VERSION` 常量） |

文件名规则不能改：wcc/wcsc 保留 `.exe`，ripgrep 无后缀。

## 换自建模块的上游源码

wcc/wcsc、skyline client、sharedMemory、float-pigment 已改为从源码构建，
源码固定在 `packages/sources.nix` 的四个 `fetchgit` 条目里（owner 都是 `msojocs`）。

```bash
# 看某个 rev 是否有更新
git ls-remote https://github.com/msojocs/wx-compiler.git HEAD
```

换 rev 后要重新填 `hash`（`fetchgit` 会报 `hash mismatch ... got:`，
把 got 的值抄回去），然后**必须重新验证产物等价性**：

- wcc/wcsc：编译同一段 wxml/wxss，与旧产物逐字节 diff
- skyline / sharedMemory / float-pigment：导出符号列表一致，
  sharedMemory 要跑一次 set/copy/remove 往返

详见 [native-modules.md](native-modules.md) 的「自建的模块」。

另外两个 Rust crate 的 `Cargo.lock` 放在 `packages/upstream/` 下
（上游仓库不提交它），换 rev 时要用新版重新生成，否则依赖版本会对不上。
