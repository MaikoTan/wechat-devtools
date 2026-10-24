# CI 与二进制缓存

## 概览

`.github/workflows/ci.yml` 在每次 push / PR 上跑三件事：

| 步骤 | 命令 | 作用 |
| --- | --- | --- |
| flake check | `nix flake check -L` | statix lint + NixOS 模块求值 + 原生模块装载 |
| build | `nix build -L .#wechat-devtools` | 完整构建 |
| smoke test | `./result/bin/wechat-devtools-cli --help` | 确认包装层与 asar 重打包没坏 |

构建产物由 [cachix-action](https://github.com/cachix/cachix-action) 推到
`maikotan` 缓存（<https://maikotan.cachix.org>）。

## 触发条件

```yaml
on:
  push:
    branches: [master]
  pull_request:
  workflow_dispatch:
```

只有 **master 的 push** 会写缓存：

```yaml
- uses: cachix/cachix-action@v17
  with:
    name: maikotan
    authToken: '${{ secrets.CACHIX_PUSH_TOKEN }}'
    skipPush: ${{ github.event_name != 'push' }}
```


## flake check 覆盖什么

`nix flake check` 跑三个 check：

| check | 作用 |
| --- | --- |
| `checks.statix` | Nix 代码 lint |
| `checks.native-modules` | 把 5 个原生模块逐个 `require` 一遍 |
| `nixosModules.default` | NixOS 模块能求值 |

`checks.native-modules` 是后来补的。CLI 的 `--help` 只打印帮助，
**不会装载 `.node`**，所以原生模块的 ABI 回归（缺 `GLIBCXX` 符号、
模块版本不匹配）在 smoke test 里完全看不见。这个 check 用 pin 里的
`nodejs_22`（与 Electron 36 内置的 Node 大版本一致）真加载一遍：

```
OK   wcc-electron/build/Release/wcc.node
OK   wcc-electron/build/Release/wcsc.node
OK   node-float-pigment-css/float-pigment-css-for-nodejs.node
OK   skyline-addon/build/skyline.node
OK   sharedMemory/sharedMemory.node
5/5 模块加载成功
```

### statix 的 W04 是坏的

`statix.toml` 里关掉了 `manual_inherit_from`（W04）。statix 0.5.8 的
W04 把路径字面量、字符串字面量、甚至**已经是 inherit 的语句**都报成
W04：

```nix
file = ./rust-toolchain.toml;              # 路径字面量，被标
inherit (sources.rustToolchain) sha256;    # 已经是 inherit，也被标
```

这些没法靠改代码消掉。新版 statix 已修掉该误报，所以直接禁用。

另外 `statix check` 的 `-c` 默认从**当前工作目录**找配置，不是从
target 目录找。check 里必须显式写 `-c ${./.}`，否则在 store 副本上
跑时读不到 `statix.toml`，W04 会全部冒出来。
PR 仍然会**读**缓存（省构建时间），只是不写。
fork PR 拿不到 `CACHIX_PUSH_TOKEN`，`authToken` 为空串，
cachix-action 此时只注册 substituter，不会报错。

## 两个必要的配置

**1. GitHub token 给 nix。** 四个自建原生模块用 `fetchgit` 从
github.com 拉源码，不带 token 会被 API 限流打挂：

```yaml
- uses: cachix/install-nix-action@v31
  with:
    extra_nix_config: |
      experimental-features = nix-command flakes
      access-tokens = github.com=${{ secrets.GITHUB_TOKEN }}
```

**2. 并发取消只对 PR。** master 推送不取消，避免打断 cachix 推送：

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

## cachix-action 的推送模式

默认 `useDaemon: true`：注册 Nix 的 post-build hook，
**边编边推**。这个包构建要几十分钟（下载 Electron zip + 编 11 个原生模块），
daemon 模式能让中途失败的运行也保留已建好的部分。

注意 daemon 模式**不会推送 substitute 下来的路径**——
这正好是我们想要的：从缓存拉下来的东西不用再推回去。

## 用户怎么用缓存

缓存名 `maikotan`，公钥：

```
maikotan.cachix.org-1:556M808HkHTnquK4IvvtfEAsej6P4mqO09ea+ncst6I=
```

一次性（当前用户）：

```bash
cachix use maikotan
```

声明式（NixOS `configuration.nix`）：

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

验证某个路径是否已在缓存里：

```bash
nix path-info --store https://maikotan.cachix.org \
  $(nix build github:MaikoTan/wechat-devtools --no-link --print-out-paths)
```

能打印出路径说明命中；报 `path ... is not valid` 说明还没推上去。

### 为什么不用 flake 的 `nixConfig`

本仓库**没有**在 `flake.nix` 里写 `nixConfig.extra-substituters`。
Nix 默认不信任 flake 提供的缓存配置，会警告并忽略：

```
warning: ignoring untrusted flake configuration setting 'extra-substituters'
```

要让它生效，用户得自己开 `accept-flake-config = true`（全局信任所有 flake，
有安全代价）或每次加 `--accept-flake-config`。与其这样，不如让用户在
系统级 `nix.settings` 里显式配一次——明确、无警告、也不需要额外权限。

## 密钥

| Secret | 用途 |
| --- | --- |
| `CACHIX_PUSH_TOKEN` | 推送到 `maikotan` 缓存 |
| `GITHUB_TOKEN` | Actions 内置，免手动配；给 nix 拉 github 源码用 |

`CACHIX_PUSH_TOKEN` 在 Cachix 的 Settings → Auth Tokens 里生成，
需要 **write** 权限。

## 本地复现 CI

```bash
# 只跑 lint
nix flake check -L

# 完整构建（不推缓存）
nix build -L .#wechat-devtools

# 手动推某个路径到缓存
nix build .#wechat-devtools --no-link --print-out-paths \
  | cachix push maikotan
```
