# WeChat Web DevTools - Unofficial Version - NixOS Module

A flake wrapper of the unofficial version of WeChat Web DevTools from [msojocs](https://github.com/msojocs/wechat-web-devtools-linux).

## Execute Directly

```bash
nix run github:MaikoTan/wechat-devtools
```

> [!NOTE]
> This package is an unfree software, you may need to add `allowUnfree = true;` in your Nix configuration,
> or append `--impure` flag to the command line.

## Flake Usage

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
    wechat-devtools
  ];
}
```
