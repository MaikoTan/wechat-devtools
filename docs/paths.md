# 路径契约

## 问题

IDE 与 CLI 是两个独立进程，靠数据目录里的握手文件通信：

- IDE 写 `<dataPath>/.ide`、`<dataPath>/.ide-status`
- CLI 写 `<dataPath>/.cli`

两边必须算出**同一个** `dataPath`，否则互相看不到对方。

## 两边的算法

### IDE 侧

`js/c47addee36149e53772b60ab7e158ffe.js`：

```js
function setBaseAppEnv(baseAppPath) {
  const baseAppDir = path.dirname(baseAppPath)
  process.env.ELECTRON_BASE_APP_PATH = baseAppPath
  process.env.ELECTRON_BASE_APP_DIR = baseAppDir
  return { baseAppPath, baseAppDir }
}

function getDataDirHash(app, baseAppPath) {
  const md5sum = crypto.createHash('md5')
  md5sum.update(baseAppPath)
  return md5sum.digest('hex')
}

function getLocalDataPath(app) {
  if (process.platform === 'win32') {
    return path.join(app.getPath('home'), 'AppData', 'Local', app.getName(), 'User Data')
  }
  return app.getPath('userData')     // ← Linux 走这里
}

function getDataPaths(app, baseAppPath) {
  const dataDirHash = getDataDirHash(app, baseAppPath)
  const dataPath = path.join(getLocalDataPath(app), dataDirHash)
  return {
    dataPath,
    defaultDataPath: path.join(dataPath, 'Default'),
    weappCodePath: path.join(dataPath, 'WeappCode'),
  }
}
```

`bootstrapAppPaths(app)` 首先调用 `setBaseAppEnv(app.getAppPath())`。

所以 IDE 侧：

```
dataPath = $XDG_CONFIG_HOME/<productName>/md5(app.getAppPath())
```

### CLI 侧

`js/common/cli/index.js` 的 Linux 分支：

```js
global.installPath = B(t)          // B(e)：e truthy 时返回 process.env.ELECTRON_BASE_APP_PATH
global.productHash = generateMd5(global.installPath)
global.electronUserDirPathRoot = join(process.env.USERPROFILE||"~",
  `AppData/Local/${userDirName}/User Data/${productHash}`)
global.userDirPath = join(global.electronUserDirPathRoot, "Default")
```

`B(e)` 的实现：

```js
function B(e) {
  if (e) {
    return process.env.ELECTRON_BASE_APP_PATH
      || join(dirname(process.execPath), "./resources/app.asar")
  }
  ...
}
```

`e` 是 `isElectron`（`process.argv.indexOf("--electron") > -1`）。

所以 CLI 侧：

```
userDirPath = <USERPROFILE>/AppData/Local/<name>/User Data/md5(ELECTRON_BASE_APP_PATH)/Default
```

## 对齐条件

两边要相等，需要：

1. **`app.getAppPath()` 与 `ELECTRON_BASE_APP_PATH` 是同一个字符串**
2. **`app.getName()` 与 `userDirName` 相同** —— 都是 `package.json` 的
   `name`/`productName` = `微信开发者工具`
3. **CLI 的 `AppData/Local/...` 重定向到 XDG** —— 这就是
   `patches/cli-data-path.js` 做的事

### 条件 1 的坑

`process.execPath` **永远是 electron 真身的路径**，即使通过符号链接或
wrapper 脚本启动（`exec` 会替换进程）。所以
`dirname(process.execPath)/resources/app.asar` 指向的是 nix store 里
electron 自己的 resources，**不是我们的 asar**。

因此：

- `$out/electron` 必须是**真实目录**（复制，不是符号链接）
- 启动器必须显式 `export ELECTRON_BASE_APP_PATH="$root_dir/electron/resources/app.asar"`

实测验证：

```js
// appPath 保留传入的路径，不做 realpath
getAppPath: /tmp/layout/electron/resources/app.asar
getName: 微信开发者工具
getPath(userData): /home/maiko/.config/微信开发者工具
```

asar 文件本身**不能**是符号链接（Electron 不跟随 asar 的符号链接）。

## 最终路径

```
$XDG_CONFIG_HOME/微信开发者工具/<md5(<root>/electron/resources/app.asar)>/
  Default/           # IDE 的 profile 目录，.ide/.cli 握手文件在这里
  WeappCode/         # 热更新代码目录
```

验证：

```bash
$ wechat-devtools-cli islogin --debug 2>&1 | grep -E "installPath|userDirPath"
[info] installPath /nix/store/.../electron/resources/app.asar
[info] userDirPath /home/maiko/.config/微信开发者工具/f98f.../Default
```

```bash
$ node -e "console.log(require('crypto').createHash('md5').update('/nix/store/.../electron/resources/app.asar').digest('hex'))"
f98f4328831ee019881bef56cd4c1b5c
```

两边 hash 一致即对齐。

## 目录创建

官方 CLI 直接 `writeFileSync(join(userDirPath, ".cli"), ...)`，不建目录；
Windows 版由启动器预先 `mkdir -p "$APPDATA/Default"`。

`patches/cli-data-path.js` 在 setter 里补了 `mkdirSync(..., { recursive: true })`，
否则首次运行会 ENOENT。
