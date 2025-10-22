{
  description = "WeChat DevTools for Linux - Unofficial version";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        pname = "wechat-devtools";
        version = "1.06.2504030-1";
        src = builtins.fetchTarball {
          url = "https://github.com/msojocs/wechat-web-devtools-linux/releases/download/v${version}/WeChat_Dev_Tools_v${version}_x86_64_linux.tar.gz";
          sha256 = "sha256-w1pgR/Ay/dIUnBdMg2YPT03CDXBM5G6ZWGBwrK6xO8E=";
        };

        extraPkgs = pkgs: [
          pkgs.nss
          pkgs.libxshmfence
        ];

        steam-run =
          (pkgs.steam.override {
            inherit extraPkgs;
          }).run;

        wrapped = pkgs.writeShellScriptBin "wechat-devtools" ''
          ${steam-run}/bin/steam-run ${pkgs.bash}/bin/bash ${src}/bin/wechat-devtools $@
        '';

        desktopItem = pkgs.makeDesktopItem {
          name = "wechat-devtools";
          exec = "${wrapped}/bin/wechat-devtools %U";
          icon = builtins.fetchurl {
            url = "https://github.com/msojocs/wechat-web-devtools-linux/raw/refs/heads/master/res/icons/wechat-devtools.svg";
            sha256 = "sha256-QuL0itqB7Ki6NhMEhIh9jkRH3hJ3Upjj4zPZzEUYlkg=";
          };
          desktopName = "WeChat Devtools";
          genericName = "WeChat Devtools";
          comment = "The development tools for wechat web develop";
          categories = [ "Development" "WebDevelopment" "IDE" ];
          terminal = false;
          startupWMClass = "nwjs_mbeenbnhnmdhkbicabncjghgnikfbgjh";
          mimeTypes = [ "x-scheme-handler/wechatide" ];
          extraConfig = {
            "Name[zh_CN]" = "微信web开发者工具";
          };
        };
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          inherit pname version;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          src = pkgs.symlinkJoin {
            name = "wechat-devtools-wrapped";
            paths = [ wrapped desktopItem ];
          };

          installPhase = ''
            runHook preInstall

            mkdir -p "$out/bin"
            mkdir -p "$out/share/applications"
            mkdir -p "$out/share/icons/hicolor/scalable/apps"

            # Copy bin files using install to ensure new files are created
            if [ -d "$src/bin" ]; then
              for f in "$src/bin"/*; do
                [ -e "$f" ] || continue
                install -D -m755 "$f" "$out/bin/$(basename "$f")"
              done
            fi

            # Copy shared data using tar pipeline to force content copy
            if [ -d "$src/share" ]; then
              mkdir -p "$out/share"
              (cd "$src/share" && tar cf - .) | (cd "$out/share" && tar xf -)
            fi

            runHook postInstall
          '';

          meta = {
            mainProgram = pname;
            platforms = [ "x86_64-linux" ];
            categories = [
              "Development"
              "IDE"
            ];
            description = "WeChat DevTools for Linux - Unofficial version";
            longDescription = ''
              WeChat DevTools for Linux - Unofficial binary version providing development tools
              for WeChat Mini Programs on Linux systems. This version uses the pre-compiled
              binary distribution.
            '';
            homepage = "https://github.com/msojocs/wechat-web-devtools-linux";
            downloadPage = "https://github.com/msojocs/wechat-web-devtools-linux/releases";
            changelog = "https://github.com/msojocs/wechat-web-devtools-linux/releases/tag/v${version}";
            license = pkgs.lib.licenses.mit; # The packaging script is under MIT License
            maintainers = [ pkgs.maintainers.maikotan ];
            sourceProvenance = with pkgs.lib.sourceTypes; [ binaryNativeCode ];
          };
        };
      }
    );
}
