# WeChat Web DevTools - Unofficial Version - NixOS Module

A flake wrapper of the unofficial version of WeChat Web DevTools from [msojocs](https://github.com/msojocs/wechat-web-devtools-linux).

# Usage

## Temporary use: 
  Do not add packages to configuration files

  `nix run github:MaikoTan/wechat-devtools`

## Permanently use:
  Add packages to your configuration flake

  ### Add `wechat-devtools` into <flake>.inputs

  ```nix
  {
    # ...
    inputs.wechat-devtools.url = "github:MaikoTan/wechat-devtools";
  }
  ```
  ### Add `wechat-devtools` by pass nix expression

  ```nix
  { # flake.nix
    inputs.nixpkgs.url = ...;
    inputs.wechat-devtools.url = "github:MaikoTan/wechat-devtools";
    
    outputs = { nixpkgs, wechat-devtools }: {
      nixosConfigurations.<machine_name> = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; }
        # ...
      };
    };
  }

  # configuration.nix or something
  { inputs, ... }: {
    environment.systemPackages = with pkgs; [ 
      vim wget curl ... 
      inputs.wechat-devtools
    ];
  }
  ```
