# WeChat DevTools for Linux

从**官方 Windows 安装包**构建的微信开发者工具 Linux 版。

思路与 [msojocs/wechat-web-devtools-linux](https://github.com/msojocs/wechat-web-devtools-linux)
一致（7z 解安装包 → 删 Windows 专有文件 → 打补丁 → asar 重打包），
但整套流程都在本仓库的 nix derivation 内可复刻，不依赖任何预打包 tarball。

## 快速开始

```bash
nix run github:MaikoTan/wechat-devtools
```

> [!NOTE]
> 微信开发者工具是 unfree 软件，需要 `allowUnfree = true;`
> （本 flake 已在内部为包开启）。

### 二进制缓存（推荐）

包由 GitHub Actions 构建并推送到 [Cachix](https://maikotan.cachix.org)，
加上缓存后 `nix run` / `nix build` 会直接下载预编译产物，不用在本地编
（要编 Electron 头文件下的 11 个原生模块，很慢）。

一次性（当前用户）：

```bash
cachix use maikotan
```

声明式（NixOS）：

```nix
{ ... }:
{
  nix.settings = {
    substituters = [ "https://maikotan.cachix.org" ];
    trusted-public-keys = [
      "maikotan.cachix.org-1:556M808HkHTnquK4IvvtfEAsej6P4mqO09ea+ncst6I="
    ];
  };
}
```

flake 用户：把 input 指过来即可，缓存走上面的 `nix.settings` 配置。

```nix
{
  inputs.wechat-devtools.url = "github:MaikoTan/wechat-devtools";
  inputs.wechat-devtools.inputs.nixpkgs.follows = "nixpkgs";
}
```

> [!NOTE]
> 本仓库的 flake 没有用 `nixConfig` 声明 substituter——Nix 默认不信任
> flake 提供的缓存配置，会警告 `ignoring untrusted flake configuration
> setting` 并忽略。所以请在系统级 `nix.settings` 里配，或用 `cachix use`。

## 用法

### 作为系统包

```nix
{ inputs.wechat-devtools.url = "github:MaikoTan/wechat-devtools"; }
```

```nix
{ pkgs, wechat-devtools }:
{
  environment.systemPackages = [ wechat-devtools.packages.x86_64-linux.default ];
}
```

### 作为 NixOS 模块

```nix
{ wechat-devtools, ... }:
{
  imports = [ wechat-devtools.nixosModules.default ];

  services.wechat-devtools.enable = true;
}
```

## 三个入口

| 命令 | 用途 |
| --- | --- |
| `wechat-devtools` | GUI 主界面 |
| `wechat-devtools-cli` | 命令行（`cli open`、`cli preview` 等） |
| `wechatide` | skill CLI（供 agent 调用） |

CLI 需要 GUI 侧开启服务端口：`设置 -> 安全设置 -> 服务端口`。

## 文档

- [构建流程](docs/build.md) —— derivation 的 8 个步骤与目录结构
- [版本固定](docs/pinning.md) —— 为什么 pin nixpkgs、Electron 36.6.0 怎么来
- [共享运行时库](docs/pinning.md#共享运行时库follows) —— 用 follows 把运行期库复用系统那份，闭包 1.7G → 1.1G
- [路径契约](docs/paths.md) —— IDE/CLI 数据目录如何对齐
- [原生模块](docs/native-modules.md) —— 7 个重编译模块、4 个自建模块与 2 个上游二进制
- [补丁说明](docs/patches.md) —— 每条补丁改什么、为什么
- [升级指南](docs/upgrade.md) —— 换版本时要核对哪些地方
- [CI 与二进制缓存](docs/ci.md) —— GitHub Actions 怎么构建、怎么推到 Cachix

## 已知限制

- `extract-file-icon` 编译产出但 Linux 上不会加载
  （官方 `dist/index.js` 只在 win32/darwin require 它）
- esbuild 官方只发 win32 变体，Linux 下不可用
- 仅支持 `x86_64-linux`
