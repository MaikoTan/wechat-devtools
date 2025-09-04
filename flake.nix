{
  description = "WeChat DevTools for Linux - Unofficial version";

  outputs = { self, nixpkgs, flake-utils }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
      };
      pname = "wechat-devtools";
      version = "1.06.2504010-2";
      src = pkgs.fetchurl {
        url = "https://github.com/msojocs/wechat-web-devtools-linux/releases/download/v${version}/WeChat_Dev_Tools_v${version}_x86_64_linux.AppImage";
        sha256 = "AQggXU24U+JAXmXKcbpYJKbfce/JVEH+dkHA0tBfvIw=";
      };
    in
    {
      packages.x86_64-linux.default = pkgs.appimageTools.wrapType2 rec {
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
            install -m 444 -D ${appimageContents}/io.github.msojocs.wechat_devtools.desktop \
              $out/share/applications/wechat-devtools.desktop
            substituteInPlace $out/share/applications/wechat-devtools.desktop \
              --replace "Exec=bin/wechat-devtools" "Exec=$out/bin/${pname}"
            install -m 444 -D ${appimageContents}/wechat-devtools.png \
              $out/share/icons/hicolor/512x512/apps/wechat-devtools.png
          '';

        meta = with pkgs.lib; {
          mainProgram = "${pname}";
          platforms = [ "x86_64-linux" ];
          categories = [ "Development" "IDE" ];
          description = "WeChat DevTools for Linux - Unofficial version";
          longDescription = ''
            WeChat DevTools for Linux - Unofficial version
          '';
          homepage = "https://github.com/msojocs/wechat-web-devtools-linux";
          license = with licenses; [
            mit # The Packaging Script is under MIT License
            unfree # WeChat DevTools is not open source software
          ];
          maintainers = with maintainers; [ MaikoTan ];
          sourceProvenance = with pkgs.lib.sourceTypes; [ binaryNativeCode ];
        };
      };
    };
}
