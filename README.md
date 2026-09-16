# WeChat DevTools for Linux - Unofficial Version

A flake wrapper of the unofficial version of WeChat DevTools from
[msojocs](https://github.com/msojocs/wechat-web-devtools-linux).

## Execute Directly

```bash
nix run github:MaikoTan/wechat-devtools
```

> [!NOTE]
> This package is an unfree software, you may need to add `allowUnfree = true;`
> in your Nix configuration, or append `--impure` flag to the command line.

## Flake Usage

### As a system package

- Add GitHub URL into `inputs` section in your `flake.nix`

```nix
{
  # ...
  inputs.wechat-devtools.url = "github:MaikoTan/wechat-devtools";
}
```

- Add `wechat-devtools` into your installed package list, for example

```nix
{ pkgs, wechat-devtools }:
{
  environment.systemPackages = [
    # ...
    wechat-devtools.packages.x86_64-linux.default
  ];
}
```

### As a NixOS module

```nix
{ pkgs, ... }:
{
  imports = [
    ./wechat-devtools/flake.nix
  ];

  services.wechat-devtools.enable = true;
}
```

When the flake is an input, use the module output directly:

```nix
{ pkgs, wechat-devtools, ... }:
{
  imports = [ wechat-devtools.nixosModules.default ];

  services.wechat-devtools.enable = true;
}
```

### Customizing the package

You can override the default source, version, desktop item, or extra dependencies
by passing arguments to the package builder:

```nix
{ pkgs, wechat-devtools }:
let
  custom = wechat-devtools.packages.x86_64-linux.default.override {
    version = "v2.01.2510290-2";
    src = pkgs.fetchurl {
      url = "https://example.com/wechat-devtools.tar.gz";
      sha256 = "sha256-...";
    };
    enableDesktopItem = false; # disable desktop integration
    extraPkgs = p: [ p.nss p.libxshmfence p.alsa-lib ];
  };
in
{
  environment.systemPackages = [ custom ];
}
```

## Package Options

| Option              | Type     | Default                                | Description                                       |
| ------------------- | -------- | -------------------------------------- | ------------------------------------------------- |
| `version`           | string   | `null` (from nvfetcher)                | Override the upstream release version.            |
| `src`               | path     | `null` (from nvfetcher)                | Override the upstream tarball source.             |
| `enableDesktopItem` | bool     | `true`                                 | Whether to install the `.desktop` file and icon.  |
| `extraPkgs`         | function | `pkgs: [ pkgs.nss pkgs.libxshmfence ]` | Extra dependencies for the steam-run wrapper.     |

## Troubleshooting

- If the icon does not appear, ensure your desktop environment supports the
  `x-scheme-handler/wechatide` MIME type.
- If the application fails to start, check that `nss` and `libxshmfence` are
  available in your Nix store.
- For debugging, run:

  ```bash
  nix store path $(nix build github:MaikoTan/wechat-devtools#packages.x86_64-linux.default)
  ```
