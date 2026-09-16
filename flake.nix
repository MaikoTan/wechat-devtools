{
  description = "WeChat DevTools for Linux - Unofficial version";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Per-system package builder
      perSystem = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              # steam-run is unfree, so enable unfree packages by default
              allowUnfree = true;
            };
          };

          # Package options for the package builder
          packageOptions = {
            enableDesktopItem = true;
            version = null;
            src = null;
            extraPkgs = pkgs: [ pkgs.nss pkgs.libxshmfence ];
          };

          package = pkgs.callPackage ./packages/default.nix {
            inherit (packageOptions) enableDesktopItem version src extraPkgs;
          };
        in
        {
          # This will become packages.<system>.default and packages.<system>.wechat-devtools
          default = package;
          wechat-devtools = package;

          # Per-system checks
          checks = {
            statix = pkgs.runCommandLocal "statix-check" {
                src = ./.;
                nativeBuildInputs = [ pkgs.statix ];
              } ''
                statix check ${./.} --config ${./.}/.statix.toml
                touch $out
              '';
          };
        }
      );

      # Top-level options (not per system)
      options = {
        enableDesktopItem = true;
        version = null;
        src = null;
        extraPkgs = pkgs: [ pkgs.nss pkgs.libxshmfence ];
      };

      # NixOS module (not system-specific)
      nixosModule = { config, pkgs, ... }: {
        imports = [ ./modules/default.nix ];
      };
    in
    perSystem // {
      options = options;
      nixosModules.default = nixosModule;
    };
}