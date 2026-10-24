# 版本固定

## 为什么 pin nixpkgs

官方 DevTools 依赖 **Electron 36.6.0** 与 Node ABI 135
（`node_module_version: 135`、`built_with_electron: 1`）。

nixpkgs unstable 的 electron 已经是 43.x：

- 原生模块对着 36.6.0 头文件编译，在 43.x 下加载会报
  "was compiled against a different Node.js version"
- `electron_36` 在 unstable 已被移除（2026-02 起 throw）

因此 flake 把 nixpkgs pin 到：

```
github:NixOS/nixpkgs/50ab793786d9de88ee30ec4e4c24fb4236fc2674
```

这是 2025-06-30 的 nixos-24.11 branch head，提供：

| 包 | 版本 |
| --- | --- |
| electron_36 | 36.4.0（我们不用它，见下） |
| nodejs_20 | 20.19.1 |
| asar | 3.2.4（与官方打包工具一致） |
| openssl | 3.3.3 |

## Electron 运行时怎么来

**不用 nixpkgs 的 electron 包**（版本对不上），直接取官方 release zip：

```nix
electronZip = fetchurl {
  url = "https://github.com/electron/electron/releases/download/v36.6.0/electron-v36.6.0-linux-x64.zip";
  sha256 = "ag3ss+OC8y1Ks9uQqr0ILvnuEVT+IFgI+IfiKP2y01U=";
};
```

官方 zip 是扁平的（无顶层目录），但 `locales/` 是唯一子目录，
stdenv 的 `sourceRoot` 自动检测会误判为多目录，显式指定：

```nix
sourceRoot = ".";
```

### RPATH

官方 zip 的二进制没有 nix 库路径，用 `autoPatchelfHook` 注入。
依赖列表与 nixpkgs 官方 electron 包的 `binary/generic.nix` 保持一致：

```nix
buildInputs = [
  alsa-lib at-spi2-atk cairo cups dbus expat gdk-pixbuf glib gtk3 gtk4
  nss nspr
  xorg.libX11 xorg.libxcb xorg.libXcomposite xorg.libXdamage
  xorg.libXext xorg.libXfixes xorg.libXrandr xorg.libxkbfile
  pango pciutils stdenv.cc.cc systemd libnotify pipewire libsecret
  libpulseaudio speechd-minimal libdrm mesa libxkbcommon libxshmfence
  libGL vulkan-loader
];
```

### sandbox

`chrome-sandbox` 随包分发。nixpkgs 的 electron wrapper 会设
`CHROME_DEVEL_SANDBOX`，我们也保留这个机制，因此**不需要** `--no-sandbox`。

msojocs 的启动器加了 `--no-sandbox`，这里刻意不加 —— userns 可用时沙箱能
正常工作，加了反而降低安全性。

## Electron 头文件

原生模块编译用，同样固定版本：

```nix
electronHeaders = fetchurl {
  url = "https://electronjs.org/headers/v36.6.0/node-v36.6.0-headers.tar.gz";
  sha256 = "11713b617ef27750c92716ab4a0cef30b4bf2ddd6b739ee95de5f918a87f4ad5";
};
```

解压后是 `node-v36.6.0/include/node/...`，`config.gypi` 里
`node_module_version: 135`、`built_with_electron: 1`。

## 升级 nixpkgs pin 时

需要重新核对：

1. `electron_36` 是否还存在（不存在就得继续 pin）
2. `asar` 的 glob 行为是否变化（`matchBase` 语义）
3. `nodejs` 内置的 node-gyp 版本（影响 `npm_config_*` 解析）
4. `autoPatchelfHook` 的依赖列表是否要跟着 nixpkgs electron 更新

## 共享运行时库（follows）

构建期依赖（electron、nodejs、rust、gcc）必须来自 pin，否则 ABI 对不上。
但**运行期依赖**（glibc、mesa、xorg、dbus、nss、cups……）没有这个限制——
它们只被 ELF 的 `DT_NEEDED` 引用，版本兼容即可。

所以 flake 把它们拆成了两个输入：

| 输入 | 用途 | 默认值 |
|------|------|--------|
| `nixpkgs` | 运行期：glibc、mesa、xorg、dbus、nss、cups | pin（`50ab793…`，2025-06-30） |
| `nixpkgsBuild` | 构建期：electron、nodejs、rust、gcc、patchelf | 同一个 pin |

`nixpkgs` 默认跟随 pin，行为与之前完全一致。
如果你想让这些库复用系统已有的那份，把它 `follows` 到你的 nixpkgs：

```nix
{
  inputs.wechat-devtools.url = "github:MaikoTan/wechat-devtools";

  inputs.wechat-devtools.inputs.nixpkgs.follows = "nixpkgs";
}
```

运行期输入故意叫 `nixpkgs` 而不是 `nixpkgsRuntime`，就是为了贴合
`inputs.<name>.inputs.nixpkgs.follows = "nixpkgs"` 这个惯用写法。
构建期那个叫 `nixpkgsBuild`，**不要** follows 它——理由见上面的 ABI 约束。

实测（nixos-unstable，glibc 2.44 / gcc 16 / mesa 26.2.5）：

| 场景 | 闭包大小 | 与系统共享路径 |
|------|----------|----------------|
| 默认（不 follows） | 1.7 GiB | 0 / 170 |
| follows 到系统 | 1.1 GiB | 142 / 158 |

省下的 600M 全部是系统里已经存在的库。

### 约束：glibc 必须一致

`autoPatchelfHook` 只改 RPATH，**不改 ELF interpreter**。
如果运行期 glibc 换了版本，解释器还指向 pin 的 `ld`，启动时会报
`GLIBC_2.43 not found`。

所以 installPhase 里显式把解释器也指向运行期 glibc：

```nix
patchelf --set-interpreter "${runtimePkgs.glibc}/lib/ld-linux-x86-64.so.2" $out/electron
```

结论：**`nixpkgs` 必须和跑这个包的系统用同一个 nixpkgs**，
不能随便指向别的版本。跨 glibc 大版本会直接起不来。

### xorg 库的路径漂移

xorg 那几个库在 nixpkgs 里的位置变过：24.11 只在 `xorg.*` 下，
26.11 挪到了顶层并废弃了 `xorg`。所以取库时写成了：

```nix
xorgLib = name: runtimePkgs.${name} or runtimePkgs.xorg.${name};
```

这样两种 nixpkgs 都能取到，也不会触发弃用警告。
