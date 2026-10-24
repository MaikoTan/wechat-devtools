#!/bin/bash
# CLI 入口。复刻官方 cli.bat 的调用契约：
#   ELECTRON_RUN_AS_NODE=1 electron -e <BOOTSTRAP> <cli.js> <user args>
#
# BOOTSTRAP 把 process.argv 重写成
#   [execPath, '--ms-enable-electron-run-as-node', cliPath, '--electron', ...userArgs]
# 这样官方 index.js 里 process.argv.slice(4) 拿到的就是用户参数，
# 且 '--electron' 让 installPath 走 ELECTRON_BASE_APP_PATH 分支。
root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

export ELECTRON_BASE_APP_PATH="$root_dir/electron/resources/app.asar"

# 官方代码读 process.env.cwd 作为「项目目录」，未设置时退回 process.cwd()。
# 启动器不 cd，所以这里把当前目录显式传进去。
if [ -z "$cwd" ]; then export cwd="$PWD"; fi

BOOTSTRAP_JS='const e=process.argv[1],a=process.argv.slice(2).filter(function(x){return x!=="--electron"});if(!process.env.cwd)process.env.cwd=process.cwd();process.argv=[process.execPath,"--ms-enable-electron-run-as-node",e,"--electron"].concat(a);require(e)'

# ELECTRON_RUN_AS_NODE=1 让 electron 以纯 node 模式运行（不初始化 GUI/X11）。
# 官方 cli.bat 也是这么做的，缺了它 electron 会把 -e 当成 Chromium 开关。
ELECTRON_RUN_AS_NODE=1 exec "$root_dir/electron/electron" -e "$BOOTSTRAP_JS" \
  "$root_dir/electron/resources/app.asar.unpacked/js/common/cli/index.js" "$@"
