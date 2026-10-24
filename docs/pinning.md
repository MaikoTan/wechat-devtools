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
