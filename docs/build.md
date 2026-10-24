# 构建流程

`packages/default.nix` 一个 derivation 走完整个流程。

## 8 个步骤

| 步骤 | 做什么 | 关键点 |
| --- | --- | --- |
| 1 | `fetchurl` 官方 `wechat_devtools_<ver>_win32_x64.exe` | url + sha256 在 `packages/sources.nix` |
| 2 | `7z` 解出 `resources/app.asar` + `app.asar.unpacked` | NSIS 包，stdenv 不认识，`unpackPhase` 被覆盖为空 |
| 3 | `asar extract` 全量解包 | 官方 asar 是混合结构，`asar extract-file` 会崩，必须整包 extract |
| 4 | 删除 Windows/macOS 专有文件 | 见下方清单 |
| 5 | 应用 `packages/patches.nix` 声明的补丁 | 见 [patches.md](patches.md) |
| 6 | 装入原生模块与预编译二进制 | 见 [native-modules.md](native-modules.md) |
| 7 | `asar pack` 重新打包 | unpack glob 与官方逐字节对齐 |
| 8 | 组装 `$out` | electron 运行时 + resources + 启动器 + desktop item |

## 删除的 Windows/macOS 专有文件

目录：

```
node_modules/keytar
node_modules/spawn-as-admin
node_modules/vscode-windows-ca-certs
node_modules/vscode-windows-registry
node_modules/vscode-windows-registry-node
node_modules/windows-process-tree
node_modules/@swc/core-win32-x64-msvc
node_modules/ios_webkit_debug_proxy
bin/adb-win
node_modules/wcc-exec        # 整个删掉重建，只保留 .exe 文件名
```

按扩展名：

```
*.lib  *.pdb  *.dll  *.exe
fsevents.node                 # macOS
conpty*.node                  # Windows
```

## asar 重打包

unpack glob 与官方 `app.asar.unpacked` 的文件清单**逐字节对齐**（537 个文件）。

```nix
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
```

两个坑：

1. **asar 的 `--unpack` 只接受一个 minimatch pattern**，多个模式必须用花括号
   包起来（`{a,b,c}`）。逗号分隔不会被解析，会静默产出 0 个解包文件。
2. **glob 不含 `package.json`** —— asar 内部用 `minimatch(filename, pattern,
   { matchBase: true })`，而 `matchBase` 让根级的 `/package.json` 匹配不上
   任何 `**/` 模式。打包后需显式复制：

   ```bash
   asar pack app app.asar --unpack '...'
   cp app/package.json app.asar.unpacked/package.json
   ```

验证方式：

```bash
find $out/electron/resources/app.asar.unpacked -type f \
  | sed "s|$out/electron/resources/app.asar.unpacked/||" | sort > built.txt
diff official.txt built.txt   # 只应差我们刻意删掉的 Windows/macOS 文件
```

## 目录结构

```
packages/
  sources.nix        所有外部产物的 url + sha256（单一来源，升级只改这里）
  native-modules.nix 对着 Electron 36.6.0 头文件编译原生模块的通用构建器
  patches.nix        对官方 asar 的所有改动，声明式列表
  default.nix        主 derivation
  launchers/         三个启动器脚本
  wechat-devtools.desktop
patches/
  cli-data-path.js        CLI 数据目录 AppData → XDG
  install-root-linux.js   installer 补 linux 平台分支
docs/                    本文档
```

## 产物布局

```
$out/
  bin/
    wechat-devtools        GUI 入口
    wechat-devtools-cli    CLI 入口
    wechatide              skill CLI 入口
  electron/                真实目录（不是符号链接）
    electron               二进制
    chrome-sandbox
    resources/
      app.asar             我们的 asar
      app.asar.unpacked/   我们的解包文件
      default_app.asar     electron 自带
  share/applications/wechat-devtools.desktop
  share/icons/hicolor/scalable/apps/wechat-devtools.svg
```

`$out/electron` 必须是真实目录，原因见 [paths.md](paths.md)。
