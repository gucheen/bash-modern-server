# Bash Modern Server

面向多台 Debian/Ubuntu 服务器的可复用 Bash 交互环境。它保留原生 Bash/Readline，在用户目录中集成 fzf、bash-autosuggestions 和 zoxide，并可选安装 Starship、eza、bat、fd、ripgrep。

默认支持 Ubuntu 24.04+ 与 Debian 13+，以发行版自带的 Bash 5.2+ 为兼容基线。

## 设计原则

- 默认安装到当前用户目录，不需要 root。
- 只在 `~/.bashrc` 添加一个有明确边界的加载块，保留原有内容。
- 不把 `ls`、`cat`、`find` 替换成其他程序。增强命令使用新名称。
- 每次安装、卸载和回滚前保留完整备份。
- 重复运行安装器只更新同一个加载块，不会重复追加配置。
- 某个增强工具缺失时静默跳过，SSH 登录仍可正常进入 Bash。

## 包含内容

| 组件 | 用途 | 默认安装方式 |
|---|---|---|
| fzf | `Ctrl+R` 模糊历史搜索及补全 | 用户目录 |
| bash-autosuggestions | 根据历史显示 fish 风格的灰色行内建议 | 用户目录编译 |
| zoxide | 使用 `z` 智能跳转目录 | 用户目录 |
| 原生 Bash 提示符 | 用户、主机、目录与失败状态 | 内置，默认启用 |
| Starship | 命令耗时及可定制提示符 | 用户目录，可选 |
| eza / bat / fd / rg | 可选的现代命令行工具 | Debian/Ubuntu 软件包 |

标准命令保持原义。新增快捷命令为：

- `ll`、`la`：目录列表；有 eza 时自动使用 eza。
- `lt`：两层目录树，仅在 eza 可用时提供。
- `bcat`：调用 `bat` 或 Debian 的 `batcat`。
- `fdf`：调用 `fd` 或 Debian 的 `fdfind`。
- `z 关键词`：由 zoxide 提供的目录跳转。

输入命令时，autosuggestions 会以灰色文字显示最近的历史匹配。按 `→`、`Ctrl+F`、`End` 或 `Ctrl+E` 接受完整建议，按 `Alt+F` 只接受下一个词。

`abbr` 提供类似 fish 的即时缩写；它与 alias 不同，会在按空格或回车时把缩写展开成可继续编辑的完整命令：

```bash
abbr gs git status
abbr --add kctx kubectl config current-context
abbr --show
abbr --erase gs
```

缩写保存在 `~/.config/bash-modern/user/abbreviations.bash`，项目更新时会保留。

默认提示符由 Bash 原生实现，只显示用户、主机、目录和失败状态，不启动额外提示符进程，也不扫描 Git 工作区；root 用户会以红色显示。提示符关闭 `promptvars`，避免目录或可选 Git 分支中的特殊内容触发命令替换。

Git 信息默认关闭。需要在提示符中显示分支、领先/落后与工作区修改时执行：

```bash
./install.sh --git-status
```

需要 Starship 的命令耗时和定制能力时执行：

```bash
./install.sh --starship
```

两项可以组合使用。普通更新会保留选择；使用 `--no-starship` 或 `--no-git-status` 可分别关闭。Starship 配置不使用 Nerd Font 图标，且关闭符号链接扫描；未启用 Git 状态时也不会加载 Git 模块。

zoxide 由编号最高的模块最后初始化，确保 Starship 等工具不会覆盖其目录变化钩子。

命令行编辑仍由 Bash 自带的 Readline 负责，不加载 ble.sh；bash-autosuggestions 只通过 Readline 的 loadable builtin 增加行内建议。内存历史保留 20,000 条、历史文件保留 50,000 条，并在多个 Bash 会话间同步。`Alt+Backspace` 删除前一个词；若终端不发送 Alt/Meta，可依次按 `Ctrl+X`、`Backspace`。对于 `/opt/docker/abc`，结果是 `/opt/docker/`。

## 快速使用

把压缩包上传到服务器后执行：

```bash
unzip bash-modern-server.zip
cd bash-modern-server
./install.sh
```

重新登录 SSH，或用新的 Bash 进程替换当前进程：

```bash
exec bash
```

检查安装状态：

```bash
~/.config/bash-modern/bin/bash-modern doctor
```

默认安装器会从各项目的上游 GitHub 仓库下载最新版，并全部放在 `~/.config/bash-modern` 内。系统已安装的同名工具也能被自动识别。Starship 只有在传入 `--starship` 或此前已经启用时才会下载。

bash-autosuggestions 需要针对服务器上的 Bash/Readline 编译。首次安装可让安装器通过 apt 准备构建依赖：

```bash
./install.sh --install-deps
```

非 root 用户会收到一次 sudo 授权请求。等价的手动命令为 `sudo apt install build-essential bash-builtins libreadline-dev pkg-config`。若直接运行默认安装且依赖缺失，安装器会跳过 autosuggestions、返回状态码 2，并提示重新使用 `--install-deps`，不会再进入注定失败的 C 编译。

编译产物会记录 Bash 完整版本。系统升级 Bash 后重新运行安装器，它会自动重编译，不会继续加载旧版本的 `.so`。

### 安装可选增强工具

如需 eza、bat、fd 和 ripgrep：

```bash
./install.sh --optional-tools
```

这一步使用 `apt`，非 root 用户会通过 `sudo` 请求授权。仓库中不存在的包会被跳过；例如部分旧版本 Debian/Ubuntu 没有 eza。核心环境不依赖这些包。

### 无网络或已有工具

只部署配置，不下载第三方组件：

```bash
./install.sh --skip-downloads
```

更新已有安装时，此选项会保留项目此前下载的 fzf、zoxide、已启用的 Starship 和 manpage。首次安装时不会下载缺失组件；系统 `PATH` 中已有的工具仍会被自动使用。

### 更新组件

在新版项目目录中运行：

```bash
./install.sh --update
```

## 多服务器部署

最简单的方式是将同一个压缩包上传到每台服务器并运行 `./install.sh`。也可以把解压后的目录放入私有 Git 仓库，在每台服务器拉取后执行安装器。

安装结果是配置副本，不依赖解压目录。安装结束后可以删除解压目录。

若需要自动化：

```bash
./install.sh --skip-downloads
```

适合离线镜像中已预装工具的场景。普通联网部署直接使用 `./install.sh`；它不要求交互，除非同时使用 `--optional-tools` 触发 sudo。

## 配置位置

```text
~/.config/bash-modern/
├── bashrc
├── bashrc.d/
├── bin/
├── vendor/
├── user/
├── starship.toml
└── starship-git.toml
```

自定义配置时，建议新增编号模块，例如：

```bash
~/.config/bash-modern/bashrc.d/50-local.sh
```

项目更新会替换项目自带配置。长期自定义内容应在安装前保存，并在自己的分支中维护对应模块。每次更新前的完整配置也会进入备份目录。

可通过环境变量改变位置：

```bash
BASH_MODERN_HOME="$HOME/.config/my-bash" ./install.sh
```

同时支持 `BASH_MODERN_BACKUP_ROOT` 和 `BASH_MODERN_BASHRC`，主要用于定制部署和测试。

## 备份与回滚

备份默认位于：

```text
~/.local/state/bash-modern/backups/
```

手动备份、查看和恢复：

```bash
~/.config/bash-modern/bin/bash-modern backup
~/.config/bash-modern/bin/bash-modern backups
~/.config/bash-modern/bin/bash-modern rollback
```

`rollback` 不带参数时恢复最新备份；也可以传入列表中的备份目录名或完整路径。恢复前还会再保存一次当前状态，因此可以撤销误操作。

## 卸载

在解压后的项目目录运行：

```bash
./uninstall.sh
```

卸载器移除 `.bashrc` 中的受管加载块和 `~/.config/bash-modern`，不会删除备份。保留配置目录：

```bash
./uninstall.sh --keep-config
```

若已经删除项目目录，也可以先从备份包重新解压，再运行卸载器。

## 故障恢复

配置异常时先启动不读取个人配置的 Bash：

```bash
bash --norc --noprofile
```

随后执行回滚，或手动删除 `~/.bashrc` 中以下两个标记之间的内容：

```text
# >>> bash-modern-server >>>
# <<< bash-modern-server <<<
```

所有集成都先检查文件或命令是否存在，因此下载或编译失败不会让新登录会话失效。安装日志会指出被跳过的组件，并以状态码 2 结束，方便自动化部署发现未完整安装；修复网络或依赖后重复运行即可。

## 安全说明

默认安装器从 fzf、bash-autosuggestions 和 zoxide 的上游 GitHub 仓库下载组件；启用 Starship 时才会访问第四个上游。fzf 和 bash-autosuggestions 使用 Git 仓库；zoxide 和 Starship 使用各自安装脚本，并把产物写入本项目的用户级目录。对版本和供应链有严格要求的环境，建议审查后在内部制品库固定这些来源，再修改 `install.sh` 的下载地址。

## 验证项目

项目包含不访问网络、也不修改真实 HOME 的流程测试：

```bash
./tests/test.sh
```

它会验证首次安装、重复安装、备份、回滚和卸载。
