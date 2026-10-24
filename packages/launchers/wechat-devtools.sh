#!/bin/bash
# GUI 入口。官方 Windows 包跑的是 <root>/wechatwebdevtools.exe，
# Linux 下直接让 electron 加载 app.asar。
root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# IDE 侧 bootstrapAppPaths() 会读 app.getAppPath() 并 export 同名变量，
# 这里显式设置是为了让 CLI 侧与 IDE 侧算出同一个 md5。
export ELECTRON_BASE_APP_PATH="$root_dir/electron/resources/app.asar"

exec "$root_dir/electron/electron" "$root_dir/electron/resources/app.asar" "$@"
