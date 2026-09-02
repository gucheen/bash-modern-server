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

## 个人命令库

命令库使用三层配置。后加载的 function 可以覆盖前一层；通过 `abbr --add` 保存的个人缩写始终优先于命令包中的同名缩写。

| 层级 | 默认位置 | 是否同步 | 适合内容 |
|---|---|---|---|
| 公开通用 | `~/.config/bash-modern/commands.d/` | 随本项目 | 不含主机信息的通用 function 和 abbr |
| 私有命令包 | `~/.config/bash-modern-commands/` | 独立私有 Git 仓库 | 内网域名、服务名、部署编排等跨服务器命令 |
| 单机配置 | `~/.config/bash-modern/user/local.sh` | 不同步 | 本机路径、角色、仅此服务器使用的 function |

安装器会更新公开通用层，并完整保留 `user/`。私有命令包位于安装目录外，因此更新和回滚 Bash Modern 时不会改动它。

仓库自带的通用命令包括：

```bash
dc <compose-arguments...>     # 通过 sudo 执行 Docker Compose
dcup                         # 更新当前 Compose 项目
dlogs [service] [lines]      # 跟随当前 Compose 项目日志
ports                        # 查看监听端口
mem                          # 查看内存
journal <service> [lines]    # 跟随 systemd 日志
```

`dc` 是所有 Compose 快捷命令的统一入口。它始终执行 `sudo docker compose`，不要求当前用户加入 `docker` 组；如果当前目录存在 `env.defaults`，会先将其作为环境文件加载，如果还存在 `.env`，则随后加载并覆盖其中的同名变量。其余参数保持原样传给 Docker Compose：

```bash
dc ps
dc up -d
dc exec web sh
```

`dcup` 和 `dlogs` 也通过 `dc` 调用 Compose，因此使用相同的 sudo 和环境文件规则。首次执行或 sudo 凭据过期时，终端会正常请求密码。

### 命令发现

在 function 或 abbr 前增加一行元数据：

```bash
# @cmd Docker | dlogs [service] [lines] | Follow Compose logs
dlogs() {
    # ...
}
```

格式固定为 `# @cmd 分类 | 用法 | 说明`。查看全部命令、搜索以及审计当前加载来源：

```bash
cmds
cmds docker
cmds --sources
```

`cmds` 只扫描已经加载且通过权限检查的 Shell 文件，不维护数据库，也不会执行额外的索引程序。

### 在 Git 命令包中声明 abbr

交互式执行 `abbr --add` 会把缩写写入本机的 `user/abbreviations.bash`。需要由 Git 管理的缩写使用只对当前 Shell 生效的声明形式，避免每次启动 Shell 时改写文件：

```bash
# @cmd Network | mtr100 <host> | Run a 100-cycle IPv4 MTR
abbr --define mtr100 'mtr -rwzc 100 -4'
```

输入 `mtr100` 后按空格或回车会展开完整命令；空格会留在编辑状态，回车会执行展开后的命令。`abbr --define` 适合写进公开或私有命令包，`abbr --add` 适合临时创建并持久化个人缩写。

### 同步私有命令包

为可能暴露服务器拓扑、服务名称或内部域名的命令单独创建私有仓库，目录结构如下：

```text
bash-modern-commands/
├── abbreviations.sh
└── commands.d/
    ├── docker.sh
    ├── network.sh
    ├── system.sh
    └── deploy.sh
```

在每台服务器克隆到默认位置：

```bash
git clone git@github.com:YOUR_ACCOUNT/bash-modern-commands.git \
    ~/.config/bash-modern-commands
chmod -R go-w ~/.config/bash-modern-commands
```

然后重新进入 Bash。同步更新应显式执行并先检查差异：

```bash
git -C ~/.config/bash-modern-commands status --short
git -C ~/.config/bash-modern-commands pull --ff-only
exec bash
```

不建议在每次 Shell 启动时自动 `git pull`：命令包是会被 `source` 的可执行代码，更新前应有人工审查边界。服务器访问私有仓库时，优先使用每台服务器独立、只读、可随时吊销的 deploy key。可通过 `BASH_MODERN_COMMANDS_HOME` 修改私有命令包位置。

私有命令包根目录、`commands.d/` 和加载的文件必须归当前用户所有，且不能由 group/other 写入；不满足条件时 Bash Modern 会跳过并给出警告。示例见 `examples/private-commands/`。

### 单机配置与敏感信息

复制模板并收紧权限：

```bash
cp examples/local.example.sh ~/.config/bash-modern/user/local.sh
chmod 600 ~/.config/bash-modern/user/local.sh
```

`local.sh` 可保存本机路径、非敏感环境变量和主机专属 function。即使是私有 Git 仓库，也不应保存 Token、密码、私钥、Cookie 或包含凭据的命令；私有仓库降低的是曝光面，不是密钥保险库。凭据应放入权限受控的专用文件或密钥管理工具，并让 CLI 通过标准的 credential file、stdin、systemd credential 等机制读取，避免出现在命令行、Shell history 和进程列表中。

公开仓库中的命令应遵守以下边界：

- 路径、服务名和目标地址通过参数或本机变量传入；
- 不出现公网 IP、内网域名、用户名、仓库地址和组织命名；
- 不包含任何认证材料，示例只使用明显的占位值；
- 合并前检查 `git diff`，必要时用 secret scanner 作为提交前或 CI 防线。

项目的 `.gitignore` 会挡住常见的 `.env`、私钥和仓库根目录下的本地配置，但它只是防误提交的最后一道提示；已经被 Git 跟踪的文件不会因 ignore 规则而变安全。

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
├── commands.d/
├── bin/
├── vendor/
├── user/
├── starship.toml
└── starship-git.toml
```

单机自定义配置使用：

```bash
~/.config/bash-modern/user/local.sh
```

项目更新会替换项目自带的 `bashrc.d/` 和 `commands.d/`，保留 `user/`。需要跨服务器同步的自定义内容应放入独立私有命令包，而不是直接修改安装目录。每次更新前的完整配置也会进入备份目录。

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
