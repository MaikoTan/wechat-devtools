/* wechat-devtools linux install-root begin */
// 官方 install-root.mjs 的 normalizePlatform / getInstallRoots / getWechatidePath
// 只认 darwin 与 win32，Linux 下直接抛「不支持的系统」。
// 这里补一个 linux 分支：安装根目录从脚本自身位置向上反查
// （同时含 bin/wechatide 与 electron/resources/app.asar.unpacked 的那一层），
// 这样无需把 $out 硬编码进补丁，nix store 路径变化也无需重新生成补丁。
// 这些函数都是 export function 声明，重新赋值即可，导入方拿到的是活绑定。
{
  // 安装根 = 同时含 bin/wechatide 与 electron/resources/app.asar.unpacked 的那一层。
  // 我们的布局是 $out/{bin,electron}，所以向上找到 electron/resources 后还要再上一层。
  const findInstallRoot = () => {
    let current = path.dirname(path.dirname(new URL('.', import.meta.url).pathname));
    for (let depth = 0; depth < 8; depth += 1) {
      if (fs.existsSync(path.join(current, 'electron', 'resources', 'app.asar.unpacked', 'package.json'))
        && fs.existsSync(path.join(current, 'bin', 'wechatide'))) {
        return current;
      }
      const parent = path.dirname(current);
      if (parent === current) break;
      current = parent;
    }
    return '';
  };


  const originalNormalizePlatform = normalizePlatform;
  normalizePlatform = (platform = process.platform) => {
    const value = String(platform).toLowerCase();
    if (['linux', 'ubuntu', 'debian', 'arch', 'nixos'].includes(value)) {
      return 'linux';
    }
    return originalNormalizePlatform(platform);
  };

  const originalGetInstallRoots = getInstallRoots;
  getInstallRoots = (platform, installRoot) => {
    if (installRoot) {
      return [installRoot];
    }
    if (platform === 'linux') {
      const root = findInstallRoot();
      return root ? [root] : [];
    }
    return originalGetInstallRoots(platform, installRoot);
  };

  const originalGetWechatidePath = getWechatidePath;
  getWechatidePath = (platform, installRoot) => {
    if (platform === 'linux') {
      return installRoot ? path.join(installRoot, 'bin', 'wechatide') : null;
    }
    return originalGetWechatidePath(platform, installRoot);
  };
}
/* wechat-devtools linux install-root end */
