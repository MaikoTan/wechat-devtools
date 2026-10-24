#!/bin/bash
# skill 入口（wechatide）。官方 macOS 用 Contents/MacOS/wechatide，
# Windows 用 wechatide.cmd，两者最终都是跑 skill-index.js。
root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

export ELECTRON_BASE_APP_PATH="$root_dir/electron/resources/app.asar"

if [ -z "$cwd" ]; then export cwd="$PWD"; fi

BOOTSTRAP_JS='const e=process.argv[1],a=process.argv.slice(2).filter(function(x){return x!=="--electron"});if(!process.env.cwd)process.env.cwd=process.cwd();process.argv=[process.execPath,"--ms-enable-electron-run-as-node",e,"--electron"].concat(a);require(e)'

# ELECTRON_RUN_AS_NODE=1 让 electron 以纯 node 模式运行（不初始化 GUI/X11）。
ELECTRON_RUN_AS_NODE=1 exec "$root_dir/electron/electron" -e "$BOOTSTRAP_JS" \
  "$root_dir/electron/resources/app.asar.unpacked/js/common/cli/skill-index.js" "$@"
