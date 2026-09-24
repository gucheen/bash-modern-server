# Bash Modern Server

面向多台 Debian/Ubuntu 服务器的 Bash 交互环境，支持 Ubuntu 24.04+、Debian 13+，以系统 Bash 5.2+ 为兼容基线。

集成历史自动建议、fzf 搜索、zoxide 目录跳转和个人命令库。默认安装到用户目录，只在 `.bashrc` 添加加载块，不替换系统 Bash，也不改变 `ls`、`cat`、`find` 等标准命令。

## 安装

将项目克隆或解压到服务器，以实际使用的用户执行：

```bash
cd bash-modern-server
./install.sh --install-deps
~/.config/bash-modern/bin/bash-modern doctor
```

`--install-deps` 通过 apt 准备自动建议的编译依赖，非 root 用户需要 sudo。依赖已齐全时直接运行 `./install.sh`。

确认状态正常后重新登录 SSH，或执行 `exec bash`。默认安装位置为 `~/.config/bash-modern`，安装完成后不依赖源码目录。

## 更新

**拉取源码后还需运行安装器，单独 `git pull` 不会更新已安装的配置。** 在每台服务器的项目源码目录执行：

```bash
git pull --ff-only
./install.sh
~/.config/bash-modern/bin/bash-modern doctor
```

使用压缩包部署时，解压新版后运行相同的安装命令。确认状态正常后重新登录，或执行 `exec bash`。

| 场景 | 安装命令 |
|---|---|
| 日常更新 | `./install.sh` |
| 只更新项目配置和脚本，保留已有第三方组件 | `./install.sh --skip-downloads` |
| 同时刷新第三方组件 | `./install.sh --update` |
| 系统 Bash 升级后重新编译自动建议 | `./install.sh`，缺依赖时加 `--install-deps` |

`--update` 不拉取本项目源码；`--skip-downloads` 不下载缺失组件，也不重编译插件。

每次安装会备份原配置，保留 `user/` 下的个人配置、缩写和功能开关。项目自带的 `bashrc.d/`、`commands.d/` 会被替换，不要在其中保存个人修改。

## 日常使用

| 功能 | 用法 |
|---|---|
| 模糊搜索历史 | `Ctrl+R` |
| 接受灰色自动建议 | `→`、`Ctrl+F`、`End` 或 `Ctrl+E`；`Alt+F` 接受下一个词 |
| 删除前一个词 | `Alt+Backspace`，或依次按 `Ctrl+X`、`Backspace` |
| 智能跳转目录 | `z 关键词` |
| 目录列表 | `ll`、`la`；有 eza 时可用 `lt` 查看两层目录树 |
| 增强文件查看与查找 | `bcat`、`fdf`，需安装 bat、fd |
| 查找可用命令 | `cmds`、`cmds docker`、`cmds --sources` |

缩写会在空格或回车时展开为完整命令，按空格后可继续编辑：

```bash
abbr --add gs git status
abbr --show
abbr --erase gs
```

个人缩写保存在 `~/.config/bash-modern/user/abbreviations.bash`，更新时保留。

内置通用命令：

```bash
dc <参数...>                # sudo docker compose
dcup                        # 更新当前 Compose 项目
dlogs [service] [lines]     # 跟随 Compose 日志
ports                       # 查看监听端口
mem                         # 查看内存
journal <service> [lines]   # 跟随 systemd 日志
```

`dc` 始终使用 sudo；当前目录有 `env.defaults` 时先加载它，再由 `.env` 覆盖同名变量。`dcup`、`dlogs` 共用这一规则。

## 可选功能

默认使用原生 Bash 提示符，显示用户、主机、目录和失败状态，不查询 Git。

```bash
./install.sh --git-status      # 提示符显示 Git 状态
./install.sh --starship        # 使用 Starship 提示符
./install.sh --optional-tools  # 通过 apt 安装 eza、bat、fd、ripgrep
```

参数可组合使用。`--no-git-status`、`--no-starship` 可分别关闭；普通更新保留已有选择。

## 个人配置与命令库

| 内容 | 位置 | 更新行为 |
|---|---|---|
| 项目通用命令 | `~/.config/bash-modern/commands.d/` | 随项目更新 |
| 跨服务器私有命令 | `~/.config/bash-modern-commands/` | 独立 Git 仓库，单独同步 |
| 单机配置 | `~/.config/bash-modern/user/local.sh` | 始终保留 |

单机配置可从模板创建：

```bash
cp examples/local.example.sh ~/.config/bash-modern/user/local.sh
chmod 600 ~/.config/bash-modern/user/local.sh
```

跨服务器命令放入独立私有仓库，在每台服务器克隆：

```bash
git clone git@github.com:YOUR_ACCOUNT/bash-modern-commands.git ~/.config/bash-modern-commands
chmod -R go-w ~/.config/bash-modern-commands
```

命令包支持根目录的 `abbreviations.sh` 和 `commands.d/*.sh`，示例见 [examples/private-commands](examples/private-commands/)。目录与文件须归当前用户所有，且不能由 group/other 写入，否则跳过加载。

在命令包中用 `abbr --define` 声明缩写，避免每次启动都写入个人配置；`# @cmd 分类 | 用法 | 说明` 可让 `cmds` 发现命令：

```bash
# @cmd Network | mtr100 <host> | Run a 100-cycle IPv4 MTR
abbr --define mtr100 'mtr -rwzc 100 -4'
```

后加载的 function 可覆盖前一层；通过 `abbr --add` 保存的个人缩写优先于命令包。私有命令包单独更新后，重新进入 Bash：

```bash
git -C ~/.config/bash-modern-commands pull --ff-only
exec bash
```

不要把密码、Token、私钥等凭据提交到命令仓库。主机专属地址和服务名放在私有命令包或单机配置中。

自定义安装位置可使用 `BASH_MODERN_HOME`；另支持 `BASH_MODERN_COMMANDS_HOME`、`BASH_MODERN_BACKUP_ROOT`、`BASH_MODERN_BASHRC`。

## 自动建议与排查

自动建议是针对系统 Bash/Readline 编译的原生插件。安装器会在隔离 Shell 中检查输入和显示行为，通过后才启用，避免输入卡住或光标错位。

普通登录只做快速缓存校验；仅动态库索引变化时核对实际依赖，相关组件变化时自动完整复检。复检可能让首次登录多等几秒，失败后不在相同环境下反复重试。系统 Bash 版本变化需重新运行安装器编译；手动关闭的功能不会自动开启。

```bash
bash-modern doctor
bash-modern autosuggestions check  # 手动复检，保留关闭选择
bash-modern autosuggestions off    # 持久关闭
bash-modern autosuggestions on     # 检测通过后启用
```

切换后重新登录或执行 `exec bash`。检测需要 Python 3、Linux `/proc` 和伪终端；自定义 `LD_PRELOAD`、`LD_LIBRARY_PATH`、`LD_AUDIT` 的环境不会放行。检测不覆盖所有终端或个人绑定组合。

下载或编译失败时，修复网络、构建依赖后重新安装；兼容性检测失败时，自动建议保持停用，其余功能仍可使用。插件来源为包含显示修复的 [gucheen/bash-autosuggestions](https://github.com/gucheen/bash-autosuggestions)。

Ubuntu 26.04 的 Bash 5.3.9 环境中已复现加载插件后按键无回显；旧版检测可能将其误报为 `suggestion at terminal right margin moves the input cursor`，新版会报告输入超时。该现象与 [Readline 8.3 的事件钩子输入缺陷](https://ftp.gnu.org/gnu/readline/readline-8.3-patches/readline83-001)一致。对于内嵌 Readline 的 Bash，仅升级 `libreadline` 或重编译插件不能修复 Bash 内的输入逻辑；需要包含相应修复的 Bash，再运行安装器和 `bash-modern autosuggestions on` 复检。

完整排查过程、此前的显示修复及自编译 Bash 的使用方式见[自动建议兼容性故障记录](docs/autosuggestions-compatibility.md)。

若输入异常导致无法操作，另开干净会话关闭自动建议：

```bash
ssh -tt 用户名@服务器地址 '/bin/bash --noprofile --norc -i'
~/.config/bash-modern/bin/bash-modern autosuggestions off
```

## 备份、回滚与卸载

安装、回滚和卸载前都会备份，默认位于 `~/.local/state/bash-modern/backups/`。

```bash
bash-modern backup
bash-modern backups
bash-modern rollback              # 恢复最新备份，也可指定备份名称或路径
```

配置异常时先运行 `bash --noprofile --norc`，再用 `~/.config/bash-modern/bin/bash-modern rollback` 恢复。完成后重新登录。

在项目源码目录卸载：

```bash
./uninstall.sh                    # 移除配置和 .bashrc 加载块，保留备份
./uninstall.sh --keep-config      # 仅移除加载块，保留配置
```

## 开发验证

本地回归测试不访问网络，也不修改真实 HOME：

```bash
./tests/test.sh
python3 -B tests/test_autosuggestions.py
python3 -B tests/test_autosuggestions_build.py
```

Linux 显示回归需要 `python3-pyte`、已编译插件；`--full-screen` 还需 Vim 和 fzf：

```bash
python3 -B tests/display_regression.py --plugin ~/.config/bash-modern/vendor/bash-autosuggestions/bash-autosuggestions.so --full-screen
```

`python3 -B tests/readline_regression.py` 会联网下载并构建不同版本的 Bash 和插件，验证已知输入、显示缺陷及修复。需要 `build-essential bash-builtins libreadline-dev pkg-config python3 git ca-certificates patch`，构建在临时目录进行。
