{
  description = "WeChat DevTools for Linux - Unofficial version";

  outputs = { self, nixpkgs, flake-utils }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
      pname = "wechat-devtools";
      version = "1.06.2412040-1";
      src = pkgs.fetchurl {
        url = "https://github.com/msojocs/wechat-web-devtools-linux/releases/download/v${version}/WeChat_Dev_Tools_v${version}_x86_64_linux.AppImage";
        sha256 = "fyOJER8xp7o4dvjaXzJSvKsZYJEDbxR0cGMbvvn8Jc8=";
      };
    in
    {
      packages.default = pkgs.appimageTools.wrapType2 rec {
        inherit pname version src;

        extraPkgs = pkgs: with pkgs; [
          gnome2.GConf
          xorg.libxkbfile
        ];

        extraInstallCommands = let
          appimageContents = pkgs.appimageTools.extractType2 {
            inherit pname version src;
          };
          in ''
            install -m 755 -D ${appimageContents}/AppRun $out/bin/${pname}
            patchShebangs $out/bin/${pname}
            install -m 444 -D ${appimageContents}/io.github.msojocs.wechat_devtools.desktop \
              $out/share/applications/wechat-devtools.desktop
            install -m 444 -D ${appimageContents}/wechat-devtools.png \
              $out/share/icons/hicolor/512x512/apps/wechat-devtools.png
          '';

        meta = with pkgs.lib; {
          mainProgram = "${pname}";
          description = "WeChat DevTools for Linux - Unofficial version";
          longDescription = ''
            WeChat DevTools for Linux - Unofficial version
          '';
          homepage = "https://github.com/msojocs/wechat-web-devtools-linux";
          # license = licenses.unfree;
          # maintainers = with maintainers; [ MaikoTan ];
          platforms = [ "x86_64-linux" ];
          sourceProvenance = with pkgs.lib.sourceTypes; [ binaryNativeCode ];
        };
      };
    }
    );
}
