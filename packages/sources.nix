# 所有外部产物的固定来源。
# 约定：这里只描述「url + sha256」，不在任何地方散落硬编码的 fetchurl，
# 升级时只需要改这一个文件（以及 packages/default.nix 里的 version）。
{
  # ── 官方 Windows 安装包（唯一的一手来源）────────────────────────
  # 版本号同时出现在 url 与 version 字段，改版本时两处都要改。
  installer = {
    version = "2.02.2608080";
    url = "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/release/be1ec64cf6184b0fa64091919793f068/wechat_devtools_2.02.2608080_win32_x64.exe";
    sha256 = "8a3255fe7626879b472dc5145e1b29d797f86d0a6bd9d775097f2ba5f9bb7467";
  };

  # ── Electron 36.6.0 头文件（编译原生模块用）────────────────────
  electronHeaders = {
    url = "https://electronjs.org/headers/v36.6.0/node-v36.6.0-headers.tar.gz";
    sha256 = "11713b617ef27750c92716ab4a0cef30b4bf2ddd6b739ee95de5f918a87f4ad5";
  };

  # ── 需要重新编译的 7 个原生模块及其依赖（npm 源）───────────────
  # 名称与官方 app.asar 内 node_modules 中实际存在的版本严格一致。
  npm = {
    "extract-file-icon@0.3.2" = {
      url = "https://registry.npmjs.org/extract-file-icon/-/extract-file-icon-0.3.2.tgz";
      sha256 = "31f103688cf382c79564854420397a8581e84562d7ce0a23302c302d9c6ec331";
    };
    "node-addon-api@1.7.1" = {
      url = "https://registry.npmjs.org/node-addon-api/-/node-addon-api-1.7.1.tgz";
      sha256 = "818d3605c09ddfdeb0080580823d32d7b66e0f5ed86180ea04d588355a79b516";
    };
    "native-keymap@3.3.2" = {
      url = "https://registry.npmjs.org/native-keymap/-/native-keymap-3.3.2.tgz";
      sha256 = "c9c18e512e14150c9418b420d975ff2216176c5404dbc02a6892e370801f70ae";
    };
    "native-watchdog@1.3.0" = {
      url = "https://registry.npmjs.org/native-watchdog/-/native-watchdog-1.3.0.tgz";
      sha256 = "72074bc2941f48eda6cc83621a4315f4b5a64e58997ace1a95ada308f0555686";
    };
    "node-pty@0.11.0-beta32" = {
      url = "https://registry.npmjs.org/node-pty/-/node-pty-0.11.0-beta32.tgz";
      sha256 = "76c52e11a46c79beb8af5ba91f3d32e912b057a03d0d49c27e391116482b4d7c";
    };
    "nan@2.23.1" = {
      url = "https://registry.npmjs.org/nan/-/nan-2.23.1.tgz";
      sha256 = "266ff71e7777f4a6e2288fb47fd283fe523c5109e0bb94d03c85f39f10f1d037";
    };
    "@vscode/spdlog@0.13.11" = {
      url = "https://registry.npmjs.org/@vscode/spdlog/-/spdlog-0.13.11.tgz";
      sha256 = "caa649647814e29c332d396e1d94bb1f84c2ce66e371bde40a054bb736c6ba06";
    };
    "bindings@1.5.0" = {
      url = "https://registry.npmjs.org/bindings/-/bindings-1.5.0.tgz";
      sha256 = "d77781178c5bd89a91b1f6c5556acd511b1b5927eb13e2ad8189cac29eeb0907";
    };
    "mkdirp@0.5.5" = {
      url = "https://registry.npmjs.org/mkdirp/-/mkdirp-0.5.5.tgz";
      sha256 = "4e5ab01a61e329dd14d4020ce846e3abd93ee79b0f788f22fd5d5b4a61b1bb0a";
    };
    "@vscode/sqlite3@5.1.4-vscode" = {
      url = "https://registry.npmjs.org/@vscode/sqlite3/-/sqlite3-5.1.4-vscode.tgz";
      sha256 = "417e8b0efc090e7698c542e9d2f3702e249cc12c2dc511484cd87bf9b088fe87";
    };
    "node-addon-api@4.3.0" = {
      url = "https://registry.npmjs.org/node-addon-api/-/node-addon-api-4.3.0.tgz";
      sha256 = "3760f2d172ef44b950ae8d3e2f932ca97f28ea8d5cc5f717451ebffd771f5cd1";
    };
    "tar@6.2.1" = {
      url = "https://registry.npmjs.org/tar/-/tar-6.2.1.tgz";
      sha256 = "d6d017a112596996d73a71f8d32112ed942877319414c0edc99ddbd816ed06e7";
    };
    "chownr@2.0.0" = {
      url = "https://registry.npmjs.org/chownr/-/chownr-2.0.0.tgz";
      sha256 = "9be25d57fe408d4db39263c0e6562447255f5639a822cf4570a2055b5dd3fc9c";
    };
    "fs-minipass@3.0.3" = {
      url = "https://registry.npmjs.org/fs-minipass/-/fs-minipass-3.0.3.tgz";
      sha256 = "413d98ddd5b14e4ad826be254208e3b376acdcb9cafb72b397dc26dc59406a58";
    };
    "minipass@7.1.2" = {
      url = "https://registry.npmjs.org/minipass/-/minipass-7.1.2.tgz";
      sha256 = "548f561a19434971254f09f21484c6bf9d1b9d037cdac62310616b351c44d516";
    };
    "minizlib@3.0.2" = {
      url = "https://registry.npmjs.org/minizlib/-/minizlib-3.0.2.tgz";
      sha256 = "fa5ce66e5149bce46b8b5938467892ed0e8c0efb058c6ea3937088c8f0efa7dd";
    };
    "mkdirp@3.0.1" = {
      url = "https://registry.npmjs.org/mkdirp/-/mkdirp-3.0.1.tgz";
      sha256 = "fc7a7c3d357bb9f265e78ef38d108f1aa2bd86e9e781d5bcc28250b3dcdc8ebf";
    };
    "yallist@4.0.0" = {
      url = "https://registry.npmjs.org/yallist/-/yallist-4.0.0.tgz";
      sha256 = "a80c78aa276536615891ef66efbc17d3bd07c8cb14e3bd5298eed3006bfa4d49";
    };
    "nodegit@0.28.0-alpha.36" = {
      url = "https://registry.npmjs.org/nodegit/-/nodegit-0.28.0-alpha.36.tgz";
      sha256 = "23ebfb7285437662be7194c68f8f17c2e5eb7e0e6005666ea4859542fcbbff03";
    };
    "@axosoft/nan@2.22.0-gk.1" = {
      url = "https://registry.npmjs.org/@axosoft/nan/-/nan-2.22.0-gk.1.tgz";
      sha256 = "6a1841dff7b343e6a2742c6ad1de5d112c74335e8ff9d3eb47a5015610412a5b";
    };
    "fs-extra@7.0.1" = {
      url = "https://registry.npmjs.org/fs-extra/-/fs-extra-7.0.1.tgz";
      sha256 = "8b28f93ef16ffc8b83e57cf3e5ce4a8124c85c27ee9cd420cf6dbe469e5d08b8";
    };
    "graceful-fs@4.2.11" = {
      url = "https://registry.npmjs.org/graceful-fs/-/graceful-fs-4.2.11.tgz";
      sha256 = "3961374aa161e6fed80d6f4b6aaf2fb7eafd2c9e5be34e865b375f0114dd099c";
    };
    "json5@2.2.3" = {
      url = "https://registry.npmjs.org/json5/-/json5-2.2.3.tgz";
      sha256 = "08afb33db600d11fc89b98fac4054f19d5d3e0fe527063116150e1ecc2d2377b";
    };
    "jsonfile@6.1.0" = {
      url = "https://registry.npmjs.org/jsonfile/-/jsonfile-6.1.0.tgz";
      sha256 = "0bd8eed33a92113fd8176b1393a5a918f725bb34fd76f9b1501b32e29bf859b3";
    };
    "universalify@2.0.0" = {
      url = "https://registry.npmjs.org/universalify/-/universalify-2.0.0.tgz";
      sha256 = "4714f7a4288d1e673159de14f4781d83972f7d46fd2cdd397b19cd102de64881";
    };
  };

  # ── 预编译的 Linux 替代二进制 ─────────────────────────────────
  # swc：官方 asar 只带 win32 变体
  swc = {
    url = "https://registry.npmjs.org/@swc/core-linux-x64-gnu/-/core-linux-x64-gnu-1.15.33.tgz";
    sha256 = "61065e7a6edda4bc8df54ce3c81ac2009ef191dc2d634e49bd90d01305059d1c";
  };

  # ripgrep：与 asar 内 @vscode/ripgrep@1.15.5 对应的官方预编译版本
  ripgrep = {
    url = "https://github.com/microsoft/ripgrep-prebuilt/releases/download/v13.0.0-10/ripgrep-v13.0.0-10-x86_64-unknown-linux-musl.tar.gz";
    sha256 = "ef820a62c1d6fdc396646762ff0f0e47e127947073ed8b5aa4ceea8b61cb1659";
  };

  # wxml/wxss 编译器（可执行文件 + node 原生模块两份）
  wcc = {
    url = "https://github.com/msojocs/wx-compiler/releases/download/v0.2.0/wcc-x86_64";
    sha256 = "6ff6b286111b1331080eb6db384e09ec50fcc1ca9d8f318219bacfae6df3f6d6";
  };
  wcsc = {
    url = "https://github.com/msojocs/wx-compiler/releases/download/v0.2.0/wcsc-x86_64";
    sha256 = "45b945bb5841b1d7c95b01fa6a5efb2ff2554ede58f00d1a07c83bf58490131b";
  };
  wccModule = {
    url = "https://github.com/msojocs/wx-compiler/releases/download/v0.2.0/wcc-x86_64.node";
    sha256 = "6d5de029f70c2171da51fe89c2057a5564b2a8024ce036df21957603cadd7f3e";
  };
  wcscModule = {
    url = "https://github.com/msojocs/wx-compiler/releases/download/v0.2.0/wcsc-x86_64.node";
    sha256 = "c5292ce334d057ded5f169d52fe5cd8d7e61f0e5eea859e065c03e2b5769516d";
  };

  # Skyline 渲染引擎的 Linux 客户端与共享内存模块
  skylineClient = {
    url = "https://github.com/msojocs/skyline-client-server/releases/download/v2.02.2608070-2/skyline-client-linux-x86_64-v2.02.2608070-2.node";
    sha256 = "ebdbfc9c205a168d58a3cfd6b5c5d79d1673ecdcb2ed1d45378dde584d03067f";
  };
  skylineSharedMemory = {
    url = "https://github.com/msojocs/skyline-shared-memory/releases/download/v1.1.0/skyline-sharedMemory-linux-x86_64-v1.1.0.node";
    sha256 = "944d74ececb937b51985cdcc6b15908c4984f6e2b517a9135b3318fe853036b2";
  };

  # wxss 的 float-pigment 解析器
  floatPigment = {
    url = "https://github.com/msojocs/float-pigment-rust/releases/download/continuous/float-pigment.linux-x64-gnu.node";
    sha256 = "03b8a958462f5273535a9a960109ed8dbf0d49f92b3d6dcc90c21ae142e054ad";
  };
}
