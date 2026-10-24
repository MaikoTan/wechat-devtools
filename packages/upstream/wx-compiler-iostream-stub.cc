// nixpkgs 的 gcc 13 头文件在 <iostream> 里声明了 _ZSt21ios_base_library_initv，
// 它只在 gcc 15 的 libstdc++ 里提供（GLIBCXX_3.4.32）。
// Electron 36.6.0 内置的 libstdc++ 是 gcc 13，最高只到 GLIBCXX_3.4.29，
// 直接链进去会让模块在 Electron 进程里加载失败。
// 这里给一个空实现：wcc/wcsc 只用 iostream 做日志输出，
// 不依赖这个初始化函数（std::cout/cerr 仍可正常工作）。
#include <cstdio>

extern "C" void _ZSt21ios_base_library_initv() {}
