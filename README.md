# RSYNC 文件传输工具 (增强版) / Enhanced Rsync Transfer Tool

这是一个增强型的 Bash 脚本，旨在简化使用 `rsync` 在不同系统间（本地、远程服务器）进行文件和目录传输的过程。它提供了一个交互式菜单，支持多种传输场景，并允许保存和重用传输配置。

## 主要特性 / Features

*   **多种传输模式**
    *   本地到服务器 (上传 / Local to Remote - Upload)
    *   服务器到本地 (下载 / Remote to Local - Download)
    *   服务器到服务器 (远程互传 / Remote to Remote)
*   **配置文件**
    *   自动创建 `servers.conf` 文件用于存储常用服务器和传输设置。
    *   启动时列出已保存的配置供快速选择。
    *   支持在配置中留空路径，在运行时提示输入。
*   **交互式配置**
    *   如果选择手动配置或配置文件不存在，脚本会引导用户完成所有必要设置。
*   **灵活认证**
    *   支持 SSH 密钥认证 (推荐 / Recommended)。
    *   支持密码认证 (需要 `sshpass` / Requires `sshpass`).
*   **用户友好**
    *   清晰的菜单和提示信息。
    *   提供默认值简化输入 (如 SSH 端口 22, 用户名 root)。
    *   路径清理功能，处理拖放到终端时可能产生的引号和转义空格。
    *   传输前显示任务摘要供用户确认。
*   **同步选项**
    *   可选择“完全同步”（使用 `--delete`，使目标与源完全一致）。
    *   可选择“增量更新”（仅添加/更新文件，不删除目标端额外文件）。
*   **配置保存 / Configuration Saving:**
    *   成功完成手动配置的传输后，可以选择将其保存到配置文件中以备后用（密码不会被保存）。

## 先决条件 / Prerequisites

1.  **Bash:** 脚本运行环境 (通常 Linux/macOS 自带)。
2.  **rsync:** 核心传输工具 (通常 Linux/macOS 自带)。如果缺失，请使用系统包管理器安装 (如 `sudo apt install rsync` 或 `sudo yum install rsync`)。
3.  **ssh client:** 用于建立安全连接 (通常 Linux/macOS 自带)。
4.  **sshpass (可选 / Optional):** **仅当**您计划使用**密码认证**时才需要。
    *   **Debian/Ubuntu:** `sudo apt-get update && sudo apt-get install sshpass`
    *   **CentOS/RHEL/Fedora:** `sudo yum install sshpass` or `sudo dnf install sshpass`
    *   **macOS (Homebrew):** `brew install hudochenkov/sshpass/sshpass-keychain` 或 `brew install esolitos/ipa/sshpass` (根据 Homebrew 版本选择)
    *   **安全警告:** 使用 `sshpass` 会在进程列表中短暂暴露密码，不如 SSH 密钥安全。**强烈建议优先使用 SSH 密钥认证。**
5.  **curl 或 wget:** 用于执行一键安装脚本。

## 安装 / Installation

### 一键安装 (推荐)

您可以使用以下任一命令将 `rsync-tool` 安装为名为 `rsynctool` 的系统命令。此脚本会下载最新版本并将其安装到用户目录 `$HOME/.local/bin` 下。

**使用 `curl`:**

```bash
curl -fsSL https://github.com/Maolipeng/rsync-tool/blob/main/install.sh | bash
```

**或使用 `wget`:**

```bash
wget -qO- https://github.com/Maolipeng/rsync-tool/blob/main/install.sh | bash
```

安装脚本将执行以下操作：

1.  下载最新的 `rsync_tool.sh` 脚本。
2.  将其放置在 `$HOME/.local/bin/rsynctool`。
3.  授予执行权限。
4.  检查 `$HOME/.local/bin` 是否在您的 `PATH` 环境变量中。如果不在，脚本会提示您如何添加（通常需要编辑 `~/.bashrc`、`~/.zshrc` 或 `~/.profile` 文件）。

安装完成后，请打开一个新的终端窗口，或重新加载您的 Shell 配置文件 (例如运行 `source ~/.bashrc` 或 `source ~/.zshrc`)。之后，您就可以通过输入以下命令来运行此工具：

```bash
rsynctool
```

### 手动安装

1.  **下载或克隆仓库:**
    ```bash
    git clone https://github.com/Maolipeng/rsync-tool.git
    cd rsync-tool
    ```
    或者直接下载 `rsync_tool.sh` 文件。
2.  **授予执行权限:**
    ```bash
    chmod +x rsync_tool.sh
    ```
3.  **运行脚本:**
    *   在当前目录运行: `./rsync_tool.sh`
    *   **(可选) 移动到 PATH 目录:** 为了能在任何位置运行，可以将脚本移动到 `PATH` 环境变量包含的目录中 (例如需要 `sudo` 的 `/usr/local/bin`，或推荐的用户本地目录 `$HOME/.local/bin`)。
      ```bash
      # 示例: 使用用户本地 bin 目录 (如果不存在则创建)
      mkdir -p "$HOME/.local/bin"
      mv rsync_tool.sh "$HOME/.local/bin/rsynctool"
      # 确保 $HOME/.local/bin 在你的 PATH 中
      # (可能需要编辑 ~/.bashrc 或 ~/.zshrc 并添加: export PATH="$HOME/.local/bin:$PATH")
      ```

## 使用方法 / Usage

1.  **运行脚本:**
    *   如果通过一键安装或移动到 PATH：
        ```bash
        rsynctool
        ```
    *   如果手动安装在当前目录：
        ```bash
        ./rsync_tool.sh
        ```
2.  **选择配置:**
    *   如果 `servers.conf` 文件存在且包含有效配置，脚本会列出它们，并带有序号。输入相应的序号选择一个已保存的配置并按 Enter。
    *   输入 `0` (或直接按 Enter，因为 0 是默认值) 选择“手动配置新传输任务”。
    *   如果 `servers.conf` 不存在或为空，脚本会自动进入手动配置流程。
3.  **手动配置流程 (如果选择 0 或首次运行):**
    *   **选择传输类型:** 根据提示输入 `1`, `2`, 或 `3` 选择传输方向。
    *   **输入源/目标信息:**
        *   根据传输类型，脚本会要求输入源和/或目标服务器的详细信息：
            *   服务器 IP 地址或域名
            *   SSH 端口 (默认为 22)
            *   用户名 (默认为 root)
            *   认证方式 (1=SSH密钥, 2=密码)
            *   SSH 密钥路径 (如果选择密钥认证，默认为 `~/.ssh/id_rsa`) 或 SSH 密码 (如果选择密码认证，输入时不会显示)。
        *   脚本会要求输入源和/或目标路径。对于本地路径，您可以将文件或文件夹直接拖拽到终端窗口 (脚本会尝试清理路径格式)。
4.  **加载配置后的流程 (如果选择了 1, 2, ...):**
    *   脚本会加载所选配置。
    *   如果配置中的**源路径**或**目标路径**为空，脚本会提示您手动输入。
    *   如果配置使用 SSH 密钥认证，脚本会验证密钥文件是否存在。如果找不到，会提示您输入新的路径或取消。
    *   如果配置使用密码认证，但配置文件中密码字段为空（推荐的安全做法），脚本会在执行传输前提示您输入密码。
5.  **选择同步方式:**
    *   选择 `1` 进行完全同步 (删除目标端多余文件)。
    *   选择 `2` (或直接按 Enter) 进行增量更新 (不删除目标端文件)。
6.  **确认传输:** 脚本会显示本次传输任务的详细摘要信息。仔细检查无误后，输入 `y` 或 `Y` 确认开始传输。输入其他任何内容将取消传输。
7.  **执行传输:** rsync 进程将开始执行，并显示进度。
8.  **保存配置 (仅限手动配置后):** 如果传输成功**并且**您是通过手动配置运行的，脚本会询问您是否要将此配置保存到 `servers.conf` 文件中。如果选择 `y`，您需要为该配置输入一个名称。

## 配置文件 (`servers.conf`)

*   **位置:** 此文件会在您**首次**运行脚本的目录下自动创建，或者在保存第一个配置时创建。如果您通过 `rsynctool` 命令运行，它通常会在您的主目录 (`~`) 或运行命令的当前目录下寻找或创建 `servers.conf`。为了方便管理，建议在特定项目目录或统一位置运行脚本。
*   **格式:** 这是一个纯文本文件，每行代表一个配置项。字段之间使用**竖线 (`|`)** 分隔。
*   **字段定义 (共 16 个字段):**

    | 字段号 | 字段名称            | 描述                                                                      | 示例 (`local_to_remote`) | 示例 (`remote_to_local`) | 示例 (`remote_to_remote`) |
    | :----- | :------------------ | :------------------------------------------------------------------------ | :----------------------- | :----------------------- | :------------------------ |
    | 1      | 名称 (Name)         | 用于标识此配置的自定义名称。                                              | `MyWebServerUpload`      | `BackupServerDownload`   | `ServerSyncJob1`          |
    | 2      | 传输类型 (Type)     | `local_to_remote`, `remote_to_local`, `remote_to_remote`                  | `local_to_remote`        | `remote_to_local`        | `remote_to_remote`        |
    | 3      | 源服务器 (Src Srv)  | 源服务器 IP 或域名。**本地传输时留空**。                                  |                          | `192.168.1.100`          | `10.0.0.1`                |
    | 4      | 源端口 (Src Port)   | 源服务器 SSH 端口。本地传输或不需要时留空。                               |                          | `22`                     | `2222`                    |
    | 5      | 源用户名 (Src User) | 源服务器 SSH 用户名。本地传输时留空。                                     |                          | `user1`                  | `syncuser`                |
    | 6      | 源认证 (Src Auth)   | 源服务器认证方式: `1`=密钥, `2`=密码。本地传输时留空。                      |                          | `1`                      | `2`                       |
    | 7      | 源密钥 (Src Key)    | 源服务器 SSH 密钥文件路径。认证方式为 1 时填写，否则留空。                  |                          | `~/.ssh/id_rsa_server1`  |                           |
    | 8      | 源密码 (Src Pass)   | 源服务器 SSH 密码。认证方式为 2 时填写。**强烈建议留空以提高安全性！**        |                          |                          |                           |
    | 9      | 源路径 (Src Path)   | 要传输的源文件或目录路径。**可以留空，运行时会提示。**                      | `/path/to/local/data/`   | `/remote/backup/files/`  | `/data/source/`           |
    | 10     | 目标服务器 (Dst Srv)| 目标服务器 IP 或域名。**本地传输时留空**。                                  | `myweb.example.com`      |                          | `10.0.0.2`                |
    | 11     | 目标端口 (Dst Port) | 目标服务器 SSH 端口。本地传输或不需要时留空。                               | `22`                     |                          | `22`                      |
    | 12     | 目标用户名 (Dst User)| 目标服务器 SSH 用户名。本地传输时留空。                                     | `webadmin`               |                          | `syncuser`                |
    | 13     | 目标认证 (Dst Auth) | 目标服务器认证方式: `1`=密钥, `2`=密码。本地传输时留空。                      | `1`                      |                          | `1`                       |
    | 14     | 目标密钥 (Dst Key)  | 目标服务器 SSH 密钥文件路径。认证方式为 1 时填写，否则留空。                  | `~/.ssh/webadmin_key`    |                          | `~/.ssh/server2_key`      |
    | 15     | 目标密码 (Dst Pass) | 目标服务器 SSH 密码。认证方式为 2 时填写。**强烈建议留空以提高安全性！**        |                          |                          |                           |
    | 16     | 目标路径 (Dst Path) | 文件或目录传输的目标路径。**可以留空，运行时会提示。**                      | `/var/www/html/`         | `/local/backups/`        | `/data/destination/`      |

*   **示例行:**

    *   **本地上传 (密钥认证，目标路径运行时输入):**
        ```
        Website Upload|local_to_remote|||||||/home/user/website/||web.example.com|22|deploy|1|~/.ssh/deploy_key|||
        ```
    *   **远程下载 (密码认证，密码和源路径运行时输入):**
        ```
        Download Logs|remote_to_local|logserver.lan|22|logreader|2|||/var/log/app/| ||||||/home/user/downloaded_logs/
        ```
    *   **服务器间同步 (源密码认证，目标密钥认证):**
        ```
        Sync Prod to Staging|remote_to_remote|10.1.1.1|22|produser|2|||/app/data/|10.2.2.2|22|stageuser|1|~/.ssh/stage_key||/app/data_staging/
        ```

*   **注意:**
    *   确保每行有 16 个字段，即使某些字段为空，也要保留 `|` 分隔符。
    *   注释行以 `#` 开头。
    *   为了安全，强烈建议将密码字段 (8 和 15) 留空。脚本会在需要时提示输入。

## 安全注意事项

*   **密码认证:** 使用密码认证 (`sshpass`) 会在执行 `rsync` 或 `scp`/`ssh` 命令时将密码作为参数传递，这可能在系统的进程列表中被其他用户看到。这是不安全的。
*   **SSH 密钥:** 使用 SSH 密钥对进行认证是更安全的选择。确保您的私钥文件 (`~/.ssh/id_rsa` 或其他) 权限设置为 `600` (仅所有者可读写)。
*   **配置文件密码:** 脚本在保存配置时**不会**保存密码字段，以避免将密码明文存储在文件中。如果您从包含密码的旧配置文件加载，脚本会使用它，但保存新配置时会将其清空。
*   **服务器到服务器 (`remote_to_remote`):**
    *   如果**目标服务器**使用密码认证，临时脚本会包含 `sshpass` 命令，这意味着 `sshpass` 需要安装在**源服务器**上。
    *   如果**源服务器**使用密码认证，`sshpass` 需要安装在运行此工具的**本地机器**上，用于 `scp` 上传脚本和 `ssh` 执行脚本。

## 故障排除 

*   **`command not found: rsynctool`:** 您可能没有将 `$HOME/.local/bin` 添加到 `PATH` 环境变量中，或者没有重新加载 shell 配置/打开新终端。请检查 `echo $PATH` 的输出，并根据安装脚本的提示操作。
*   **`servers.conf: No such file or directory` 或找不到配置:** 配置文件 `servers.conf` 默认在运行脚本的当前目录下查找或创建。请确保您在正确的目录下运行 `rsynctool`，或者将 `servers.conf` 移动到您运行命令的位置。
*   **`sshpass: command not found`:** 您选择了密码认证，但 `sshpass` 未安装。请参照 [先决条件](#先决条件--prerequisites) 部分进行安装。对于 `remote_to_remote`，请检查是在本地机器还是源服务器上缺少 `sshpass`。
*   **`Permission denied (publickey,password)`:** SSH 连接失败。检查：
    *   服务器地址、端口、用户名是否正确。
    *   如果是密钥认证：密钥路径是否正确？密钥文件是否存在且权限正确 (`chmod 600 private_key`)？公钥是否已添加到远程服务器的 `~/.ssh/authorized_keys` 文件中？
    *   如果是密码认证：密码是否输入正确？
    *   防火墙是否阻止了 SSH 连接？
*   **`rsync: connection unexpectedly closed`:** 通常是 SSH 连接中断或远程 `rsync` 进程出错。检查网络连接和远程服务器的 `rsync` 是否可用。
*   **`No such file or directory`:**
    *   如果是本地源路径 (local_to_remote)，检查该路径在本地是否确实存在。
    *   如果是远程路径，请确保您在远程服务器上的路径拼写正确且有权访问。
*   **路径包含空格或特殊字符:** 脚本尝试清理拖放的路径，但手动输入的复杂路径可能需要您自己用引号括起来或进行转义。
*   **配置文件格式错误:** 脚本在加载配置时会检查字段数量。如果提示 "字段数不足"，请检查 `servers.conf` 中对应行的 `|` 数量是否正确 (应有 15 个 `|`，构成 16 个字段)。

## 卸载

如果您是通过**一键安装脚本**安装的 `rsynctool`：

```bash
rm -f "$HOME/.local/bin/rsynctool"
echo "rsynctool uninstalled."
```

如果您是**手动安装**到其他位置的，只需删除对应的脚本文件（例如 `rsynctool` 或 `rsync_tool.sh`）。

**注意:** 卸载脚本**不会**删除您的 `servers.conf` 配置文件。如果您不再需要它，请手动删除该文件。

## 贡献

欢迎提出改进建议或报告问题。您可以通过本项目的 GitHub Issues 提交反馈或 Pull Requests。
