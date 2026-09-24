# 自动建议兼容性故障记录

## 故障现象

WSL2 的 Ubuntu 26.04 中，Bash `5.3.9(1)-release` 加载自动建议插件时，检测报告：

```text
incompatible; disabled (suggestion at terminal right margin moves the input cursor)
```

插件来源为 [gucheen/bash-autosuggestions](https://github.com/gucheen/bash-autosuggestions)，提交为 `4db0812f9f5f1a6c2ab7a6603c85fc97ccb763e0`。该提交已经包含此前的显示修复，刷新旧插件不是这次问题的解决办法。

## 此前的修复

早期插件确实存在右边缘光标错位。终端打印完最后一列后，通常要等下一个可打印字符出现才换行；插件提前把换行计入行数，恢复光标时就可能上移到错误位置。

显示修复让插件在恢复光标前完成待处理的换行，项目随后切换到包含修复的插件分支。

项目同时通过隔离伪终端检查输入与显示，通过后才加载插件。检测结果会缓存，Bash、插件或相关依赖变化后重新验证；用户手动关闭的选择会保留。构建失败时清除旧二进制，避免旧插件继续被当作可加载版本。

## 本次定位：输入卡住被误报为显示错误

在 Ubuntu 26.04 ARM64 容器中，用同样的 Bash 版本和插件提交复现了故障。用户环境为 WSL2 x86_64，因此该现象不依赖 WSL2 或 Windows Terminal。

检测使用固定 120 列的伪终端。观察输出发现，加载插件后按键没有回显，纯输入检测也超时。原来的显示检测在输入字符后短暂等待，再检查光标是否前进；输入未被处理时，光标没有移动，于是被误报为右边缘光标错位。

修正后的检测先等待终端响应，没有响应时报告：

```text
interactive input timed out (no terminal response after typing)
```

自动停用仍然保留，因为输入功能确实未正常工作。

## 根因与验证

GNU 的 [readline83-001 补丁](https://ftp.gnu.org/gnu/readline/readline-8.3-patches/readline83-001)修复了事件钩子持续运行、却没有读取已到达输入的问题。补丁前后对照验证如下：

| Bash 与插件组合 | 结果 |
|---|---|
| 未修复输入逻辑的 Bash + 插件 | 输入超时 |
| 修复输入逻辑的 Bash + 旧插件 | 真实的右边缘光标错位 |
| 修复输入逻辑的 Bash + 已修复插件 | 输入与显示检测通过 |

本次报错修正的 27 项单元测试及端到端回归均通过。测试入口：

```bash
python3 -B tests/test_autosuggestions.py
python3 -B tests/readline_regression.py
```

端到端回归需要 Linux、网络和构建依赖，会下载源码并编译补丁前后的 Bash。验证完成于测试环境，不代表用户的 WSL 环境已经修复。

## 恢复方式

复现环境的 Bash 内嵌 Readline。仅升级系统 `libreadline` 或重新编译插件，不会替换 Bash 内部的输入逻辑；需要使用包含相应修复的 Bash。

实际验证通过的组合为 **Bash 5.3.9 + readline83-001 输入修复**。编译方法可参照 `tests/readline_regression.py`：在 Bash 5.3 源码上依次应用 `bash53-001` 至 `bash53-009`，然后向 `lib/readline/input.c` 应用 `readline83-001` 的对应修改，跳过独立 Readline 库的 `patchlevel` 文件。

2026-09-24 核对的 [GNU 官方补丁目录](https://ftp.gnu.org/gnu/bash/bash-5.3-patches/)已到 `bash53-020`。可以应用全部补丁构建 Bash 5.3.20，但当时核对的 010～020 未包含本次输入修复，仍需单独应用。5.3.20 加该修复的组合未在本次回归中验证，安装后应重新检测。

建议将自编译版本安装到 `~/.local/opt/bash-fixed`，保留系统 `/bin/bash`。直接覆盖系统文件会影响使用 `#!/bin/bash` 的脚本，也会造成包管理记录与实际文件不一致，后续系统升级还可能覆盖自编译文件。

编译时使用以下配置，并安装插件所需的头文件：

```bash
../configure \
  --prefix="$HOME/.local/opt/bash-fixed" \
  --libdir="$HOME/.local/opt/bash-fixed/lib" \
  --without-bash-malloc
make -j"$(nproc)"
make install
make install-headers
```

上述命令在打好补丁的 Bash 源码目录下新建的 `build` 子目录中执行。独立目录安装不需要 `sudo make install`。

新 Bash 安装完成后，在本项目源码目录执行：

```bash
(
  set -e
  export PATH="$HOME/.local/opt/bash-fixed/bin:$PATH"
  export PKG_CONFIG_PATH="$HOME/.local/opt/bash-fixed/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

  pkg-config --variable=includedir bash
  "$HOME/.local/opt/bash-fixed/bin/bash" ./install.sh --update
  "$HOME/.local/opt/bash-fixed/bin/bash" \
    "${BASH_MODERN_HOME:-$HOME/.config/bash-modern}/bin/bash-modern" \
    autosuggestions on
)
```

`pkg-config` 应指向用户目录中的 `bash-fixed/include`。首次切换保留 `--update`：新旧 Bash 的版本字符串可能相同，需要强制重新编译插件。检测通过后，再进入新 Bash：

```bash
exec "$HOME/.local/opt/bash-fixed/bin/bash"
```

## 登录 Shell 与后续更新

修改用户登录 Shell，不保证安装脚本会使用新 Bash：

| 配置 | 作用 |
|---|---|
| `chsh` | 选择用户登录时启动的 Shell |
| `PATH` | 选择 `#!/usr/bin/env bash` 脚本使用的 Bash |
| `PKG_CONFIG_PATH` | 选择插件编译时查找的 Bash 头文件 |

可以保留系统 Bash，仅把自编译版本设为个人登录 Shell。全局把新 Bash 放到 `PATH` 最前面，还会影响其他 `#!/usr/bin/env bash` 脚本；写死 `#!/bin/bash` 的脚本仍使用系统版本。

如果只希望安装器使用新 Bash，日常更新时临时指定环境：

```bash
PATH="$HOME/.local/opt/bash-fixed/bin:$PATH" \
PKG_CONFIG_PATH="$HOME/.local/opt/bash-fixed/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
"$HOME/.local/opt/bash-fixed/bin/bash" ./install.sh
```

日常更新不必每次重复 `--update`、`autosuggestions on` 和切换 Shell。首次切换运行环境时完成重编译与验证；需要刷新第三方组件时再使用 `--update`。
