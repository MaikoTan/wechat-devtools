# 对官方 app.asar 内容的所有改动，集中声明在这里。
#
# 设计原则：
#   1. 只做「让官方 Windows 产物在 Linux 上跑起来」所必需的最小改动，
#      不重排、不美化、不引入官方没有的行为。
#   2. 每条改动都是纯文本操作（prepend / append / replace），
#      因此可以逐条审计，升级版本时只需重新核对目标字符串是否漂移。
#   3. 补丁脚本本身不包含 $out 等构建期路径：安装根目录一律由脚本在运行时
#      自行反查（见 install-root-linux.js），nix store 路径变化无需重新生成补丁。
#
# 约定：file 统一相对 app.asar 解包后的根目录。
{ patchDir }:

let
  # 读取补丁脚本内容，供 prepend/append 使用。
  readPatch = name: builtins.readFile (patchDir + "/${name}");

  # 一条改动。字段含义：
  #   file     —— 目标文件（相对 asar 根）
  #   op       —— prepend | append | replace
  #   content  —— prepend/append 时插入的文本
  #   from/to  —— replace 时的查找/替换字符串（均为纯字符串，非正则）
  #   note     —— 人类可读的改动理由，升级时用来判断是否仍然必要
  patch = file: op: arg: note: { inherit file op note; } // arg;
in
{
  # ── CLI 数据目录：Windows AppData → XDG ────────────────────────
  # 官方 CLI 的 Linux 分支仍按 Windows 风格拼
  #   <USERPROFILE>/AppData/Local/<name>/User Data/<hash>[/Default]
  # 这里重定向到 $XDG_CONFIG_HOME/<name>/<hash>[/Default]，
  # 与 IDE 侧 app.getPath('userData') + md5(appPath) 的算法对齐，
  # 否则 CLI 与 IDE 会各写各的数据目录，.ide/.cli 握手文件互相看不到。
  cliDataPath = patch "js/common/cli/index.js" "prepend" {
    content = readPatch "cli-data-path.js";
  } "CLI 主入口：把 AppData 风格的数据目录改到 XDG";

  # skill-index.js 与 index.js 的初始化结构不同（前者由 electronUserDirPathRoot
  # 派生 userDirPath），但两者最终都会给这两个 global 赋值，
  # 因此同一段补丁通用。
  skillCliDataPath = patch "js/common/cli/skill-index.js" "prepend" {
    content = readPatch "cli-data-path.js";
  } "skill CLI 入口：同上";

  # ── 安装根目录反查：补 linux 分支 ──────────────────────────────
  # 官方 install-root.mjs 的 normalizePlatform / getInstallRoots / getWechatidePath
  # 只认 darwin 与 win32，Linux 下直接抛「不支持的系统」。
  # 这些函数都是 export function 声明，重新赋值即可，导入方拿到的是活绑定。
  installRootLinux = patch "wechatide-skill/skills/installer/scripts/install-root.mjs" "append" {
    content = readPatch "install-root-linux.js";
  } "installer：补 linux 平台分支，从脚本位置向上反查安装根";

  # ── PATH 安装：Linux 走 unix 软链而非写注册表 ──────────────────
  # ensure-cli-path.mjs 的 main() 是
  #   options.platform === 'darwin' ? ensureDarwin(install) : ensureWin32(install)
  # Linux 会落进 ensureWin32，进而调用 readWindowsUserPath()（powershell.exe），
  # 在 Linux 上必然抛错。ensureDarwin 的逻辑（/usr/local/bin → ~/.local/bin 软链）
  # 对 Linux 完全适用，因此把三分元的选择条件改成包含 linux。
  ensureCliPathLinux = patch "wechatide-skill/skills/installer/scripts/ensure-cli-path.mjs" "replace" {
    from = "options.platform === 'darwin'";
    to = "options.platform !== 'win32'";
  } "ensure-cli-path：Linux 与 macOS 一样走 unix 软链分支";

  # ── skill CLI 的 argv 偏移 ─────────────────────────────────────
  # skill-index.js 的 g() 从 process.argv[2] 开始找 tool 名，
  # 但官方 cli.bat 的 BOOTSTRAP 会把 argv 重写成
  #   [execPath, '--ms-enable-electron-run-as-node', cliPath, '--electron', ...userArgs]
  # 共 4 个前缀元素，于是 argv[2]（cliPath）被误当成 tool 名。
  # index.js 用 slice(A?3:4) 正确处理了这一点，skill-index.js 漏了。
  # 官方 wechatidecli.cmd 指向 index.js 所以从未暴露此问题；
  # 我们单独提供 wechatide 入口跑 skill-index.js，必须把偏移改成 4。
  skillArgvOffset = patch "js/common/cli/skill-index.js" "replace" {
    from = "for(let n=2;n<e.length;n+=1)";
    to = "for(let n=4;n<e.length;n+=1)";
  } "skill CLI：修正 BOOTSTRAP 引入的 argv 前缀偏移";
}
