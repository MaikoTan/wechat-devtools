/* wechat-devtools linux cli data path begin */
// 官方 CLI 的 Linux 分支仍按 Windows 风格拼
//   <USERPROFILE>/AppData/Local/<name>/User Data/<hash>[/Default]
// 这里把它重定向到 XDG 配置目录，并保留 <hash> 层级，
// 以便与 IDE 侧 app.getPath('userData') 写出的 .ide/.cli 对齐。
// index.js 与 skill-index.js 的初始化结构不同（后者由 electronUserDirPathRoot
// 派生 userDirPath），但两者最终都会给这两个 global 赋值，因此同一段补丁通用。
(() => {
  const path = require('path');
  const os = require('os');
  const configHome = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');

  const toXdg = (value) => {
    if (typeof value !== 'string') return value;
    const matched = value.match(
      /AppData[/\\]Local[/\\]([^/\\]+)[/\\]User Data[/\\]([0-9a-f]+)([/\\]Default)?$/
    );
    if (!matched) return value;
    return path.join(configHome, matched[1], matched[2], matched[3] ? 'Default' : '');
  };

  for (const key of ['electronUserDirPathRoot', 'userDirPath']) {
    const stash = `_${key}`;
    Object.defineProperty(global, key, {
      configurable: true,
      enumerable: true,
      get() { return this[stash]; },
      set(value) {
        const next = toXdg(value);
        this[stash] = next;
        // 官方 CLI 直接往 <userDirPath>/.cli 写握手文件，不负责建目录；
        // Windows 版由启动器预先 mkdir。这里补上，否则首次运行会 ENOENT。
        try {
          require('fs').mkdirSync(next, { recursive: true });
        } catch (e) {
          // 目录建不出来时不要中断初始化，交给后续写入时报更准确的错。
        }
      },
    });
  }
})();
/* wechat-devtools linux cli data path end */
