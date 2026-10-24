// 冒烟测试：把每个自建/重编译的原生模块 require 一遍。
// CLI 的 --help 只打印帮助，不会装载 .node，原生模块的 ABI 回归抓不到。
// 用法：node smoke-test.mjs <app.asar.unpacked 的路径>

import { createRequire } from "node:module";
import { join } from "node:path";

const unpacked = process.argv[2];
if (!unpacked) {
  console.error("usage: node smoke-test.mjs <app.asar.unpacked>");
  process.exit(2);
}

// 解析基准点，文件本身不需要存在。
const require = createRequire(join(unpacked, "node_modules", "__smoke__.js"));

// [相对 node_modules 的路径, 必须存在的导出]
// wcc/wcsc 是 C++ 写的内部接口，加载成功即算通过，不强求导出。
const modules = [
  ["wcc-electron/build/Release/wcc.node", []],
  ["wcc-electron/build/Release/wcsc.node", []],
  ["node-float-pigment-css/float-pigment-css-for-nodejs.node", ["compile"]],
  ["skyline-addon/build/skyline.node", ["Controller"]],
  ["sharedMemory/sharedMemory.node", ["setMemory"]],
];

let failed = 0;
for (const [rel, expected] of modules) {
  const file = join(unpacked, "node_modules", rel);
  try {
    const mod = require(file);
    const missing = expected.filter((key) => !(key in mod));
    if (missing.length > 0) {
      console.error(`FAIL ${rel}: 缺少导出 ${missing.join(", ")}`);
      failed++;
    } else {
      console.log(`OK   ${rel}`);
    }
  } catch (err) {
    console.error(`FAIL ${rel}: ${String(err.message).split("\n")[0]}`);
    failed++;
  }
}

console.log(`${modules.length - failed}/${modules.length} 模块加载成功`);
process.exit(failed === 0 ? 0 : 1);
