# Bash Modern Server

面向多台 Debian/Ubuntu 服务器的可复用 Bash 交互环境。它保留原生 Bash/Readline，在用户目录中集成 fzf、zoxide 和 Starship，并可选安装 eza、bat、fd、ripgrep。

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
| zoxide | 使用 `z` 智能跳转目录 | 用户目录 |
| Starship | Git 状态等提示符信息 | 用户目录 |
| eza / bat / fd / rg | 可选的现代命令行工具 | Debian/Ubuntu 软件包 |

标准命令保持原义。新增快捷命令为：

- `ll`、`la`：目录列表；有 eza 时自动使用 eza。
- `lt`：两层目录树，仅在 eza 可用时提供。
- `bcat`：调用 `bat` 或 Debian 的 `batcat`。
- `fdf`：调用 `fd` 或 Debian 的 `fdfind`。
- `z 关键词`：由 zoxide 提供的目录跳转。

默认提示符针对服务器管理做了精简，只显示用户、主机、目录、Git 分支与状态、慢命令耗时和失败状态。它不使用 Nerd Font 图标，也不会随项目目录自动加入语言版本等模块；root 用户会以红色显示。

zoxide 由编号最高的模块最后初始化，确保 Starship 等工具不会覆盖其目录变化钩子。

命令行编辑完全交给 Bash 自带的 Readline，不再加载 ble.sh。内存历史保留 20,000 条、历史文件保留 50,000 条，并在多个 Bash 会话间同步。`Alt+Backspace` 删除前一个词；若终端不发送 Alt/Meta，可依次按 `Ctrl+X`、`Backspace`。对于 `/opt/docker/abc`，结果是 `/opt/docker/`。

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

默认安装器会从各项目的官方 GitHub 仓库下载最新版，并全部放在 `~/.config/bash-modern` 内。系统已安装的同名工具也能被自动识别。

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

更新已有安装时，此选项会保留项目此前下载的 fzf、zoxide、Starship 和 manpage。首次安装时不会下载缺失组件；系统 `PATH` 中已有的工具仍会被自动使用。

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
└── starship.toml
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

所有集成都先检查文件或命令是否存在，因此下载失败不会让新登录会话失效。安装日志会指出被跳过的组件，并以状态码 2 结束，方便自动化部署发现未完整安装；修复网络或依赖后重复运行即可。

## 安全说明

安装器只从三个项目的官方 GitHub 仓库下载组件。fzf 使用官方 Git 仓库；zoxide 和 Starship 使用各自官方安装脚本，并把二进制写入本项目的用户级目录。对版本和供应链有严格要求的环境，建议审查后在内部制品库固定这些来源，再修改 `install.sh` 的下载地址。

## 验证项目

项目包含不访问网络、也不修改真实 HOME 的流程测试：

```bash
./tests/test.sh
```

它会验证首次安装、重复安装、备份、回滚和卸载。
