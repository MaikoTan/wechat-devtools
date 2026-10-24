# 补丁说明

所有改动集中在 `packages/patches.nix` 声明，每条都是纯文本操作
（`prepend` / `append` / `replace`），可逐条审计。

设计原则：

1. 只做「让官方 Windows 产物在 Linux 上跑起来」所必需的最小改动，
   不重排、不美化、不引入官方没有的行为
2. 补丁脚本本身不含 `$out` 等构建期路径，安装根目录由脚本在运行时自行反查，
   nix store 路径变化无需重新生成补丁
3. 升级版本时只需重新核对目标字符串是否漂移

## 1. CLI 数据目录：AppData → XDG

**文件**：`js/common/cli/index.js`、`js/common/cli/skill-index.js`
**操作**：prepend `patches/cli-data-path.js`

官方 CLI 的 Linux 分支仍按 Windows 风格拼：

```js
global.electronUserDirPathRoot = join(process.env.USERPROFILE||"~",
  `AppData/Local/${userDirName}/User Data/${productHash}`)
global.userDirPath = join(global.electronUserDirPathRoot, "Default")
```

补丁用 `Object.defineProperty` 在这两个 global 上装 setter，
把 `AppData/Local/<name>/User Data/<hash>[/Default]` 重写为
`$XDG_CONFIG_HOME/<name>/<hash>[/Default]`，与 IDE 侧
`app.getPath('userData') + md5(appPath)` 的算法对齐。

两个文件的初始化结构不同（`skill-index.js` 由 `electronUserDirPathRoot`
派生 `userDirPath`），但两者最终都会给这两个 global 赋值，因此同一段补丁通用。

setter 里还补了 `mkdirSync(..., { recursive: true })` ——
官方 CLI 直接写 `.cli` 不建目录，Windows 版由启动器预先 mkdir。

详见 [paths.md](paths.md)。

## 2. installer 补 linux 平台分支

**文件**：`wechatide-skill/skills/installer/scripts/install-root.mjs`
**操作**：append `patches/install-root-linux.js`

官方 `normalizePlatform` / `getInstallRoots` / `getWechatidePath`
只认 darwin 与 win32，Linux 下直接抛「不支持的系统」。

补丁重新赋值这三个 `export function`（导入方拿到的是活绑定）：

- `normalizePlatform`：把 `linux`/`ubuntu`/`debian`/`arch`/`nixos` 归一为 `linux`
- `getInstallRoots`：从脚本自身位置向上反查安装根
- `getWechatidePath`：返回 `<installRoot>/bin/wechatide`

安装根的判定条件是「同时含 `bin/wechatide` 与
`electron/resources/app.asar.unpacked/package.json` 的那一层」，
对应我们的 `$out/{bin,electron}` 布局。

`getPackagePaths` 的 win32 分支（`resources/app.asar.unpacked/package.json`）
对 Linux 同样适用，无需改。

## 3. ensure-cli-path：Linux 走 unix 软链

**文件**：`wechatide-skill/skills/installer/scripts/ensure-cli-path.mjs`
**操作**：replace

```js
// from
options.platform === 'darwin'
// to
options.platform !== 'win32'
```

官方 `main()` 是：

```js
const payload = options.platform === 'darwin' ? ensureDarwin(install) : ensureWin32(install)
```

Linux 会落进 `ensureWin32`，进而调用 `readWindowsUserPath()`
（`spawnSync('powershell.exe', ...)`），在 Linux 上必然抛错。

`ensureDarwin` 的逻辑（`/usr/local/bin` → `~/.local/bin` 软链 + 写 shell rc）
对 Linux 完全适用，所以把三分元条件改成包含 linux。

## 4. skill CLI 的 argv 偏移

**文件**：`js/common/cli/skill-index.js`
**操作**：replace

```js
// from
for(let n=2;n<e.length;n+=1)
// to
for(let n=4;n<e.length;n+=1)
```

`skill-index.js` 的 `g(e)` 从 `process.argv[2]` 开始找 tool 名，
但官方 `cli.bat` 的 BOOTSTRAP 会把 argv 重写成：

```
[execPath, '--ms-enable-electron-run-as-node', cliPath, '--electron', ...userArgs]
```

共 4 个前缀元素，于是 `argv[2]`（cliPath）被误当成 tool 名。

`index.js` 用 `slice(A?3:4)` 正确处理了这一点，`skill-index.js` 漏了。
官方 `wechatidecli.cmd` 指向 `index.js`，所以从未暴露此问题；
我们单独提供 `wechatide` 入口跑 `skill-index.js`，必须把偏移改成 4。

## 未采用的补丁

msojocs 的 patch 里还有一些改动这里**刻意不做**：

| 改动 | 原因 |
| --- | --- |
| 改 `package.json` 的 `name` | 官方 IDE/CLI 两侧都用同一个 `name`，无需统一 |
| `js/extensions/skyline/index.js` 的 `"win32"===window.__global.platform` | 该变量在模块内从未被使用（死代码），所有同名 `r` 都是参数遮蔽 |
| webview touch/mouse-leave 修复 | 目标 bundle 文件未定位，且非必需 |

## 启动器里去掉的包装

msojocs 的启动器有一堆额外逻辑，这里刻意去掉：

| 包装 | 原因 |
| --- | --- |
| `WECHAT_DEVTOOLS_DIR` | 官方代码不读 |
| `USERPROFILE` / `APPDATA` | Windows 路径概念，Linux 无用 |
| 缓存清理 + `.build_time` 比对 | 会删用户数据，且 nix store 只读 |
| `USERDATADIR` | 官方代码不读 |
| `PATH` 注入 + `cd $root_dir/bin` | 官方代码不依赖 |
| AppImage 的 `tail -f /etc/issue` | 只对 AppImage 有必要 |
| `--no-sandbox` | `chrome-sandbox` 随包分发，沙箱能正常工作 |

保留的核心契约：

- `ELECTRON_BASE_APP_PATH` 指向 `<root>/electron/resources/app.asar`
- `BOOTSTRAP_JS` 复刻官方 `cli.bat` 的 argv 重写逻辑
- `ELECTRON_RUN_AS_NODE=1`（CLI/skill 入口，缺了它 electron 会尝试启 GUI）
