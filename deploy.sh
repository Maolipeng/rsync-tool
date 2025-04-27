#!/bin/bash

# 脚本标题和简介
echo "====================================="
echo "  RSYNC 文件传输工具 (增强版)"
echo "====================================="
echo "此脚本支持本地到服务器、服务器到本地、服务器到服务器的文件传输。"
echo

# 清理路径函数（处理拖放到终端的路径）
clean_path() {
    local path="$1"
    # 去除路径首尾的引号
    path="${path%\"}"
    path="${path#\"}"
    path="${path%\'}"
    path="${path#\'}"
    # 替换转义的空格
    path="${path//\\ / }"
    echo "$path"
}

# 检查配置文件是否存在
CONFIG_FILE="$(dirname "$0")/servers.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    touch "$CONFIG_FILE"
    echo "# 服务器配置文件" > "$CONFIG_FILE"
    echo "# 格式: 名称|传输类型|源服务器|源端口|源用户名|源认证方式|源密钥|源密码(安全起见建议留空)|源路径|目标服务器|目标端口|目标用户名|目标认证方式|目标密钥|目标密码(安全起见建议留空)|目标路径" >> "$CONFIG_FILE"
    echo "# 传输类型: local_to_remote, remote_to_local, remote_to_remote" >> "$CONFIG_FILE"
    echo "# 认证方式: 1=SSH密钥, 2=密码" >> "$CONFIG_FILE"
    echo "# 注意: 路径可以留空，运行时会提示输入。密码字段建议留空，运行时会提示输入。" >> "$CONFIG_FILE"
fi

# 定义变量，用于标记是否已经从配置中选择服务器
MANUAL_CONFIG=true # Default to manual unless config is chosen

# 选择传输类型
select_transfer_type() {
    local TRANSFER_CHOICE
    # Print prompts/menu to stderr so they are not captured by command substitution
    echo "请选择传输类型:" >&2
    echo "1) 本地到服务器 (上传)" >&2
    echo "2) 服务器到本地 (下载)" >&2
    echo "3) 服务器到服务器 (远程传输)" >&2
    read -p "选择 (1-3): " TRANSFER_CHOICE

    # Echo the RESULT value to stdout (this WILL be captured)
    case $TRANSFER_CHOICE in
        1) echo "local_to_remote" ;;
        2) echo "remote_to_local" ;;
        3) echo "remote_to_remote" ;;
        *) echo "local_to_remote" ;;  # Default case returns the value to stdout
    esac
}


# 获取服务器信息
get_server_info() {
    local prefix="$1"  # 源/目标前缀
    local SERVER_ADDRESS SSH_PORT SERVER_USER AUTH_METHOD KEY_PATH PASSWORD RETRY

    # 获取地址
    read -p "请输入${prefix}服务器IP地址或域名: " SERVER_ADDRESS

    # 获取端口
    read -p "请输入${prefix}SSH端口 [默认22]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}

    # 获取远程用户名
    read -p "请输入${prefix}服务器用户名 [默认root]: " SERVER_USER
    SERVER_USER=${SERVER_USER:-root}

    # 获取认证方式
    echo "请选择${prefix}服务器认证方式:" >&2 # Print to stderr
    echo "1) SSH密钥认证" >&2
    echo "2) 密码认证" >&2
    read -p "选择 (1 或 2): " AUTH_METHOD

    KEY_PATH=""
    PASSWORD=""

    if [ "$AUTH_METHOD" = "1" ]; then
        # 密钥认证
        while true; do
            read -p "请输入${prefix}SSH密钥路径 [默认~/.ssh/id_rsa]: " KEY_PATH
            KEY_PATH=${KEY_PATH:-~/.ssh/id_rsa}

            # 展开波浪号为用户主目录
            KEY_PATH="${KEY_PATH/#~/$HOME}"

            # 验证密钥文件是否存在
            if [ ! -f "$KEY_PATH" ]; then
                echo "错误: 无法访问SSH密钥文件: $KEY_PATH" >&2 # Print error to stderr
                read -p "是否重新输入密钥路径? (y/n): " RETRY
                if [ "$RETRY" != "y" ] && [ "$RETRY" != "Y" ]; then
                    echo "操作已取消。" >&2
                    # Return an indicator of failure or exit? Returning empty might be ambiguous
                    # Let's exit here for clarity in get_server_info failure
                    exit 1
                fi
            else
                break
            fi
        done
    elif [ "$AUTH_METHOD" = "2" ]; then
        # 密码认证，使用sshpass
        if ! command -v sshpass &> /dev/null; then
            echo "错误: 未找到sshpass命令。请先安装sshpass。" >&2
            echo "安装命令: sudo apt-get install sshpass (Debian/Ubuntu)" >&2
            echo "或: sudo yum install sshpass (CentOS/RHEL)" >&2
            echo "或: brew install hudochenkov/sshpass/sshpass (mac,默认通过 homebrew 安装)" >&2
            exit 1
        fi

        read -sp "请输入${prefix}SSH密码: " PASSWORD
        echo >&2 # Print newline to stderr after password input
    else
      echo "错误：无效的认证方式选择。" >&2
      exit 1
    fi

    # 返回服务器信息的数组 (to stdout, this is captured)
    echo "$SERVER_ADDRESS|$SSH_PORT|$SERVER_USER|$AUTH_METHOD|$KEY_PATH|$PASSWORD"
}

# 获取路径信息 - 修改为支持可选路径
get_path_info() {
    local path_type="$1"  # 源/目标路径
    local default_path="$2"  # 配置中的默认路径，可能为空
    local INPUT_PATH CLEAN_PATH CONTINUE

    if [ -z "$default_path" ]; then
        read -p "请输入${path_type}路径: " INPUT_PATH
    else
        read -p "请输入${path_type}路径 [默认: $default_path]: " INPUT_PATH
        if [ -z "$INPUT_PATH" ]; then
            INPUT_PATH="$default_path"
        fi
    fi

    # 清理可能拖放到终端的路径
    CLEAN_PATH=$(clean_path "$INPUT_PATH")

    # 如果是本地路径并且是源路径，验证路径存在
    # Important: Need TRANSFER_TYPE to be correctly set before calling this for local source check
    if [[ "$path_type" == *"源"* ]] && [[ "$TRANSFER_TYPE" == "local_to_remote" ]] && [ ! -e "$CLEAN_PATH" ]; then
        echo "警告: 找不到指定的本地文件/文件夹: $CLEAN_PATH" >&2
        read -p "是否继续? (y/n): " CONTINUE
        if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
            echo "操作已取消。" >&2
            exit 1 # Exit if user doesn't want to continue with non-existent source
        fi
    fi
    # Return path to stdout
    echo "$CLEAN_PATH"
}

# 执行rsync传输
perform_transfer() {
    local SYNC_METHOD DELETE_OPTION SYNC_TYPE RSYNC_OPTIONS SSH_CMD TMP_SCRIPT DST_SSH_CMD SSH_EXIT_CODE rsync_exit_code

    # 获取同步方式
    echo "请选择同步方式:" >&2
    echo "1) 完全同步 (删除目标目录中源目录不存在的文件)" >&2
    echo "   - 适用场景: 当您希望目标目录与源目录完全一致" >&2
    echo "   - 注意: 此选项会删除目标目录中在源目录不存在的文件" >&2
    echo "2) 增量更新 (只添加和更新文件，不删除目标目录中的文件)" >&2
    echo "   - 适用场景: 当您只想更新或添加文件，保留目标目录中的其他文件" >&2
    read -p "选择 (1 或 2) [默认2]: " SYNC_METHOD
    SYNC_METHOD=${SYNC_METHOD:-2}

    # 根据同步方式设置rsync选项
    if [ "$SYNC_METHOD" = "1" ]; then
        DELETE_OPTION="--delete"
        SYNC_TYPE="完全同步"
    else
        DELETE_OPTION=""
        SYNC_TYPE="增量更新"
    fi

    # 设置rsync基本选项
    RSYNC_OPTIONS="-avz --progress $DELETE_OPTION"

    # 询问是否需要排除文件夹
    local EXCLUDE_OPTION=""
    local EXCLUDE_INPUT
    local IFS=',' # 设置分隔符为逗号
    read -p "是否需要排除某些文件夹或文件? (y/n) [默认n]: " EXCLUDE_CHOICE
    if [[ "$EXCLUDE_CHOICE" == "y" || "$EXCLUDE_CHOICE" == "Y" ]]; then
        read -p "请输入要排除的模式 (多个模式用逗号分隔, 例如 'node_modules,.git,*.log'): " EXCLUDE_INPUT
        # 去除首尾空格
        EXCLUDE_INPUT=$(echo "$EXCLUDE_INPUT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$EXCLUDE_INPUT" ]; then
            for pattern in $EXCLUDE_INPUT; do
                # 去除模式周围可能存在的空格
                pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [ -n "$pattern" ]; then
                    # Corrected quoting for exclude pattern
                    EXCLUDE_OPTION="$EXCLUDE_OPTION --exclude=$pattern"
                fi
            done
        fi
    fi
    unset IFS # 恢复默认分隔符

    # 将排除选项添加到RSYNC_OPTIONS
    RSYNC_OPTIONS="$RSYNC_OPTIONS $EXCLUDE_OPTION"

    # 根据传输类型执行rsync
    case $TRANSFER_TYPE in
        local_to_remote)
            echo "执行本地到服务器的传输..." >&2

            # 设置SSH选项
            if [ "$DST_AUTH_METHOD" = "1" ]; then
                # 使用密钥认证
                SSH_CMD="ssh -p $DST_SSH_PORT -i '$DST_KEY_PATH'" # Quote key path
            else
                # 使用密码认证
                 # Check if password is empty (might happen if loaded from config without password saved)
                if [ -z "$DST_PASSWORD" ]; then
                    read -sp "请输入目标服务器SSH密码: " DST_PASSWORD
                    echo >&2
                fi
                if ! command -v sshpass &> /dev/null; then echo "错误: sshpass 命令未找到." >&2; exit 1; fi
                SSH_CMD="sshpass -p '$DST_PASSWORD' ssh -p $DST_SSH_PORT"
            fi

            # 执行rsync
            echo "执行命令: rsync $RSYNC_OPTIONS -e \"$SSH_CMD\" \"$SRC_PATH\" \"$DST_USER@$DST_SERVER:$DST_PATH\"" >&2
            rsync $RSYNC_OPTIONS -e "$SSH_CMD" "$SRC_PATH" "$DST_USER@$DST_SERVER:$DST_PATH"
            rsync_exit_code=$?
            ;;

        remote_to_local)
            echo "执行服务器到本地的传输..." >&2

            # 设置SSH选项
            if [ "$SRC_AUTH_METHOD" = "1" ]; then
                # 使用密钥认证
                SSH_CMD="ssh -p $SRC_SSH_PORT -i '$SRC_KEY_PATH'" # Quote key path
            else
                # 使用密码认证
                if [ -z "$SRC_PASSWORD" ]; then
                    read -sp "请输入源服务器SSH密码: " SRC_PASSWORD
                    echo >&2
                fi
                 if ! command -v sshpass &> /dev/null; then echo "错误: sshpass 命令未找到." >&2; exit 1; fi
                SSH_CMD="sshpass -p '$SRC_PASSWORD' ssh -p $SRC_SSH_PORT"
            fi

            # 执行rsync
            echo "执行命令: rsync $RSYNC_OPTIONS -e \"$SSH_CMD\" \"$SRC_USER@$SRC_SERVER:$SRC_PATH\" \"$DST_PATH\"" >&2
            rsync $RSYNC_OPTIONS -e "$SSH_CMD" "$SRC_USER@$SRC_SERVER:$SRC_PATH" "$DST_PATH"
            rsync_exit_code=$?
            ;;

        remote_to_remote)
            echo "执行服务器到服务器的传输..." >&2

            # 检查工具是否安装
            if ! command -v sshpass &> /dev/null && { [ "$SRC_AUTH_METHOD" = "2" ] || [ "$DST_AUTH_METHOD" = "2" ]; }; then
                echo "错误: 密码认证需要sshpass，但未找到该命令。" >&2
                exit 1
            fi

            # 获取密码（如果需要且为空）
            if [ "$SRC_AUTH_METHOD" = "2" ] && [ -z "$SRC_PASSWORD" ]; then
                read -sp "请输入源服务器SSH密码: " SRC_PASSWORD
                echo >&2
            fi
             if [ "$DST_AUTH_METHOD" = "2" ] && [ -z "$DST_PASSWORD" ]; then
                read -sp "请输入目标服务器SSH密码: " DST_PASSWORD
                echo >&2
            fi


            # 创建临时脚本
            TMP_SCRIPT=$(mktemp /tmp/rsync_remote_XXXXXX.sh)
            if [ -z "$TMP_SCRIPT" ] || [ ! -w "$TMP_SCRIPT" ]; then
                echo "错误：无法创建临时文件。" >&2
                exit 1
            fi


            # 创建目标服务器SSH命令
            if [ "$DST_AUTH_METHOD" = "1" ]; then
                # 目标使用密钥认证
                DST_SSH_CMD="ssh -p $DST_SSH_PORT -i '$DST_KEY_PATH'" # Quote key path

                # 创建临时脚本内容 (使用密钥)
                # Use standard /bin/sh for better portability
                cat > "$TMP_SCRIPT" << EOF
#!/bin/sh
# 自动生成的远程到远程rsync脚本 (目标使用密钥)

# 执行rsync
echo "在源服务器上执行: rsync $RSYNC_OPTIONS -e \"$DST_SSH_CMD\" \"$SRC_PATH\" \"$DST_USER@$DST_SERVER:$DST_PATH\"" >&2
rsync $RSYNC_OPTIONS -e "$DST_SSH_CMD" "$SRC_PATH" "$DST_USER@$DST_SERVER:$DST_PATH"
EOF
            else
                # 目标使用密码认证
                # Ensure DST_PASSWORD has a value here
                if [ -z "$DST_PASSWORD" ]; then echo "内部错误：目标密码在创建脚本时为空" >&2; rm -f "$TMP_SCRIPT"; exit 1; fi
                # Use standard /bin/sh for better portability
                cat > "$TMP_SCRIPT" << EOF
#!/bin/sh
# 自动生成的远程到远程rsync脚本 (目标使用密码)

# 检查并执行rsync
# Note: sshpass needs to be installed on the SOURCE server for this to work
if ! command -v sshpass >/dev/null 2>&1; then
    echo "错误: 源服务器 '${SRC_SERVER}' 上缺少 sshpass 命令，无法进行目标密码认证。" >&2
    exit 1
fi
echo "在源服务器上执行: sshpass -p '******' rsync $RSYNC_OPTIONS -e \"ssh -p $DST_SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null\" \"$SRC_PATH\" \"$DST_USER@$DST_SERVER:$DST_PATH\"" >&2
sshpass -p '$DST_PASSWORD' rsync $RSYNC_OPTIONS -e "ssh -p $DST_SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" "$SRC_PATH" "$DST_USER@$DST_SERVER:$DST_PATH"
# Added SSH options to potentially avoid host key issues during automated run
EOF
            fi

            # 设置脚本权限
            chmod +x "$TMP_SCRIPT"

             # 设置源服务器SSH选项并上传执行脚本
            SSH_EXIT_CODE=1 # Default to error
            if [ "$SRC_AUTH_METHOD" = "1" ]; then
                # 源服务器使用密钥认证
                echo "正在上传脚本到源服务器 $SRC_SERVER ..." >&2
                scp -P "$SRC_SSH_PORT" -i "$SRC_KEY_PATH" "$TMP_SCRIPT" "$SRC_USER@$SRC_SERVER:/tmp/"
                if [ $? -ne 0 ]; then echo "错误: 上传脚本到源服务器失败。" >&2; rm -f "$TMP_SCRIPT"; exit 1; fi

                echo "正在源服务器上执行传输脚本..." >&2
                ssh -p "$SRC_SSH_PORT" -i "$SRC_KEY_PATH" "$SRC_USER@$SRC_SERVER" "sh /tmp/$(basename "$TMP_SCRIPT")" # Use sh
                SSH_EXIT_CODE=$? # Capture exit code of remote script

                echo "正在清理源服务器上的临时脚本..." >&2
                ssh -p "$SRC_SSH_PORT" -i "$SRC_KEY_PATH" "$SRC_USER@$SRC_SERVER" "rm -f /tmp/$(basename "$TMP_SCRIPT")"

            elif [ "$SRC_AUTH_METHOD" = "2" ]; then
                # 源服务器使用密码认证
                if [ -z "$SRC_PASSWORD" ]; then echo "内部错误：源密码在传输时为空" >&2; rm -f "$TMP_SCRIPT"; exit 1; fi
                if ! command -v sshpass &> /dev/null; then echo "错误: 本地 sshpass 命令未找到." >&2; rm -f "$TMP_SCRIPT"; exit 1; fi
                echo "正在上传脚本到源服务器 $SRC_SERVER ..." >&2
                sshpass -p "$SRC_PASSWORD" scp -P "$SRC_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$TMP_SCRIPT" "$SRC_USER@$SRC_SERVER:/tmp/"
                 if [ $? -ne 0 ]; then echo "错误: 上传脚本到源服务器失败。" >&2; rm -f "$TMP_SCRIPT"; exit 1; fi

                echo "正在源服务器上执行传输脚本..." >&2
                sshpass -p "$SRC_PASSWORD" ssh -p "$SRC_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SRC_USER@$SRC_SERVER" "sh /tmp/$(basename "$TMP_SCRIPT")" # Use sh
                SSH_EXIT_CODE=$? # Capture exit code of remote script

                echo "正在清理源服务器上的临时脚本..." >&2
                sshpass -p "$SRC_PASSWORD" ssh -p "$SRC_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SRC_USER@$SRC_SERVER" "rm -f /tmp/$(basename "$TMP_SCRIPT")"
            fi

            # 清理本地临时文件
            rm -f "$TMP_SCRIPT"

            # 检查传输结果 (based on remote execution exit code)
            if [ $SSH_EXIT_CODE -eq 0 ]; then
                echo "远程传输任务成功完成！" >&2
                return 0
            else
                echo "远程传输过程中出现错误 (来自远程执行，退出码: $SSH_EXIT_CODE)。" >&2
                return $SSH_EXIT_CODE
            fi
            ;;
        *)
            echo "内部错误：perform_transfer 中遇到未知传输类型 '$TRANSFER_TYPE'" >&2
            return 1
            ;;
    esac

    # 检查传输结果 (for local_to_remote and remote_to_local which don't use SSH_EXIT_CODE var)
    if [ $rsync_exit_code -eq 0 ]; then
        echo "传输任务成功完成！" >&2
        return 0
    else
        echo "传输过程中出现错误 (rsync 退出码: $rsync_exit_code)。" >&2
        return $rsync_exit_code
    fi
}

# 验证密钥文件
verify_key_path() {
    local key_path="$1"
    local prefix="$2"
    local RETRY new_key_path corrected_key_path

    if [ -n "$key_path" ]; then
        # 展开波浪号为用户主目录
        corrected_key_path="${key_path/#~/$HOME}"

        # 验证密钥文件是否存在
        if [ ! -f "$corrected_key_path" ]; then
            echo "错误: 无法访问${prefix}SSH密钥文件: $corrected_key_path" >&2
            read -p "是否手动输入新的密钥路径? (y/n): " RETRY
            if [ "$RETRY" = "y" ] || [ "$RETRY" = "Y" ]; then
                read -p "请输入新的${prefix}SSH密钥路径: " new_key_path
                 # Clean and expand new path
                 new_key_path=$(clean_path "$new_key_path")
                 new_key_path="${new_key_path/#~/$HOME}"

                if [ ! -f "$new_key_path" ]; then
                    echo "错误: 仍然无法访问SSH密钥文件: $new_key_path" >&2
                    echo "操作已取消。" >&2
                    return 1 # Indicate failure
                fi
                echo "$new_key_path" # Return corrected path to stdout
                return 0 # Indicate success
            else
                echo "操作已取消。" >&2
                return 1 # Indicate failure
            fi
        else
             # Key exists, return it
             echo "$corrected_key_path" # Return existing valid path to stdout
             return 0 # Indicate success
        fi
    else
        # No key path provided in config, this is fine
        echo "" # Return empty string to stdout
        return 0 # Indicate success (nothing to verify)
    fi
}

# --- 主逻辑 ---

CONFIG_CHOICE="" # Initialize config choice

# 显示配置列表
if [ -f "$CONFIG_FILE" ]; then
    echo "检测到服务器配置文件:"
    echo "------------------------"
    # 过滤注释和空行，只显示有效配置
    VALID_SERVERS=$(grep -v "^#" "$CONFIG_FILE" | grep -v "^$")
    SERVER_COUNT=0
    declare -a SERVER_LINES # Array to store valid lines

    if [ -z "$VALID_SERVERS" ]; then
        echo "配置文件中没有有效配置。"
    else
        while IFS= read -r line; do
            # Basic validation: check for minimum number of fields (e.g., at least name and type)
            if [[ "$(echo "$line" | awk -F'|' '{print NF}')" -ge 16 ]]; then # Check for expected number of fields
                 ((SERVER_COUNT++))
                 SERVER_LINES[$SERVER_COUNT]="$line" # Store line with 1-based index

                 # Use awk for simplicity here, ensure it handles empty fields correctly
                 SERVER_NAME=$(echo "$line" | awk -F'|' '{print $1}')
                 TRANSFER_TYPE_DISPLAY=$(echo "$line" | awk -F'|' '{print $2}')
                 SRC_PATH_DISPLAY=$(echo "$line" | awk -F'|' '{print $9}')
                 DST_PATH_DISPLAY=$(echo "$line" | awk -F'|' '{print $16}')
                 SRC_SERVER_DISPLAY=$(echo "$line" | awk -F'|' '{print $3}')
                 DST_SERVER_DISPLAY=$(echo "$line" | awk -F'|' '{print $10}')

                 # 获取服务器显示信息
                 SRC_INFO="未知"
                 DST_INFO="未知"
                 case $TRANSFER_TYPE_DISPLAY in
                     local_to_remote)
                         SRC_INFO="本地"
                         DST_INFO="$DST_SERVER_DISPLAY"
                         [ -z "$DST_INFO" ] && DST_INFO="(目标服务器未设置)"
                         ;;
                     remote_to_local)
                         SRC_INFO="$SRC_SERVER_DISPLAY"
                         DST_INFO="本地"
                          [ -z "$SRC_INFO" ] && SRC_INFO="(源服务器未设置)"
                         ;;
                     remote_to_remote)
                         SRC_INFO="$SRC_SERVER_DISPLAY"
                         DST_INFO="$DST_SERVER_DISPLAY"
                         [ -z "$SRC_INFO" ] && SRC_INFO="(源服务器未设置)"
                         [ -z "$DST_INFO" ] && DST_INFO="(目标服务器未设置)"
                         ;;
                 esac

                 # 显示路径信息，检查是否为空
                 [ -z "$SRC_PATH_DISPLAY" ] && SRC_PATH_DISPLAY="(路径未设置)"
                 [ -z "$DST_PATH_DISPLAY" ] && DST_PATH_DISPLAY="(路径未设置)"

                 echo "$SERVER_COUNT) $SERVER_NAME ($SRC_INFO → $DST_INFO) [$SRC_PATH_DISPLAY → $DST_PATH_DISPLAY]"
            else
                echo "警告: 跳过格式无效的配置行 (字段数不足): $line" >&2
            fi
        done <<< "$VALID_SERVERS"
    fi

    echo "0) 手动配置新传输任务"
    echo "------------------------"
    read -p "请选择配置 (输入序号) [默认 0]: " CONFIG_CHOICE
    CONFIG_CHOICE=${CONFIG_CHOICE:-0} # Default to 0 if input is empty

    if [[ "$CONFIG_CHOICE" =~ ^[1-9][0-9]*$ ]] && [ "$CONFIG_CHOICE" -le "$SERVER_COUNT" ]; then
        # 加载选定的配置
        CONFIG_INFO="${SERVER_LINES[$CONFIG_CHOICE]}"

        # 解析配置信息 using IFS
        IFS='|' read -r PROFILE_NAME TRANSFER_TYPE \
                        SRC_SERVER SRC_SSH_PORT SRC_USER SRC_AUTH_METHOD SRC_KEY_PATH SRC_PASSWORD SRC_PATH \
                        DST_SERVER DST_SSH_PORT DST_USER DST_AUTH_METHOD DST_KEY_PATH DST_PASSWORD DST_PATH <<< "$CONFIG_INFO"

        # Trim potential leading/trailing whitespace from parsed fields (important!)
        PROFILE_NAME=$(echo "$PROFILE_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        TRANSFER_TYPE=$(echo "$TRANSFER_TYPE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        SRC_SERVER=$(echo "$SRC_SERVER" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        SRC_SSH_PORT=$(echo "$SRC_SSH_PORT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        SRC_USER=$(echo "$SRC_USER" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        SRC_AUTH_METHOD=$(echo "$SRC_AUTH_METHOD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        SRC_KEY_PATH=$(echo "$SRC_KEY_PATH" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Do not trim password fields
        SRC_PATH=$(echo "$SRC_PATH" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        DST_SERVER=$(echo "$DST_SERVER" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        DST_SSH_PORT=$(echo "$DST_SSH_PORT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        DST_USER=$(echo "$DST_USER" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        DST_AUTH_METHOD=$(echo "$DST_AUTH_METHOD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        DST_KEY_PATH=$(echo "$DST_KEY_PATH" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Do not trim password fields
        DST_PATH=$(echo "$DST_PATH" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')


        echo "已加载配置: $PROFILE_NAME"
        MANUAL_CONFIG=false # Config was loaded
    else
        if [ "$CONFIG_CHOICE" != "0" ]; then
             echo "无效的选择 '$CONFIG_CHOICE'。将进行手动配置。" >&2
        fi
        # 选择手动配置 (0 or invalid input treated as 0)
        CONFIG_CHOICE="0"
        MANUAL_CONFIG=true
    fi
else
    # 配置文件不存在，进行手动配置
    echo "未找到配置文件 $CONFIG_FILE，将进行手动配置。" >&2
    MANUAL_CONFIG=true
    CONFIG_CHOICE="0" # Ensure config choice reflects manual mode
fi


# 如果选择了手动配置 (选项0)
if [ "$CONFIG_CHOICE" = "0" ]; then
    echo
    echo "--- 开始手动配置 ---"

    # 完全重置所有变量，确保没有残留的预设值
    PROFILE_NAME=""
    TRANSFER_TYPE=""
    SRC_SERVER="" SRC_SSH_PORT="" SRC_USER="" SRC_AUTH_METHOD="" SRC_KEY_PATH="" SRC_PASSWORD="" SRC_PATH=""
    DST_SERVER="" DST_SSH_PORT="" DST_USER="" DST_AUTH_METHOD="" DST_KEY_PATH="" DST_PASSWORD="" DST_PATH=""

    # 设置 MANUAL_CONFIG 标志，用于后续判断是否保存
    MANUAL_CONFIG=true # Ensure this is definitively true here

    # 1. 选择传输类型 (必须询问) - This now works correctly
    TRANSFER_TYPE=$(select_transfer_type)
    if [ -z "$TRANSFER_TYPE" ]; then echo "错误：未能确定传输类型。" >&2; exit 1; fi

    # 2. 根据传输类型获取源和目标信息 (必须询问)
    case $TRANSFER_TYPE in
        local_to_remote)
            # 获取源路径 (需要 TRANSFER_TYPE 已设置)
            SRC_PATH=$(get_path_info "源(本地)" "")
             if [ $? -ne 0 ]; then exit 1; fi # Exit if get_path_info caused exit

            # 获取目标服务器信息
            DST_INFO=$(get_server_info "目标")
            if [ $? -ne 0 ]; then exit 1; fi # Exit if get_server_info failed
            IFS='|' read -r DST_SERVER DST_SSH_PORT DST_USER DST_AUTH_METHOD DST_KEY_PATH DST_PASSWORD <<< "$DST_INFO"

            DST_PATH=$(get_path_info "目标(远程)" "")
             if [ $? -ne 0 ]; then exit 1; fi
            ;;

        remote_to_local)
            # 获取源服务器信息
            SRC_INFO=$(get_server_info "源")
             if [ $? -ne 0 ]; then exit 1; fi
             IFS='|' read -r SRC_SERVER SRC_SSH_PORT SRC_USER SRC_AUTH_METHOD SRC_KEY_PATH SRC_PASSWORD <<< "$SRC_INFO"

            SRC_PATH=$(get_path_info "源(远程)" "")
            if [ $? -ne 0 ]; then exit 1; fi

            DST_PATH=$(get_path_info "目标(本地)" "")
            if [ $? -ne 0 ]; then exit 1; fi
            ;;

        remote_to_remote)
            # 获取源服务器信息
            SRC_INFO=$(get_server_info "源")
            if [ $? -ne 0 ]; then exit 1; fi
             IFS='|' read -r SRC_SERVER SRC_SSH_PORT SRC_USER SRC_AUTH_METHOD SRC_KEY_PATH SRC_PASSWORD <<< "$SRC_INFO"

            SRC_PATH=$(get_path_info "源(远程)" "")
            if [ $? -ne 0 ]; then exit 1; fi

            # 获取目标服务器信息
            DST_INFO=$(get_server_info "目标")
             if [ $? -ne 0 ]; then exit 1; fi
             IFS='|' read -r DST_SERVER DST_SSH_PORT DST_USER DST_AUTH_METHOD DST_KEY_PATH DST_PASSWORD <<< "$DST_INFO"

            DST_PATH=$(get_path_info "目标(远程)" "")
            if [ $? -ne 0 ]; then exit 1; fi
            ;;
        *)
            echo "错误：未知的传输类型 '$TRANSFER_TYPE'" >&2
            exit 1
            ;;
    esac
    echo "--- 手动配置完成 ---"

else
    # --- 使用已加载的配置 ---
    local KEY_VERIFIED NEW_KEY_PATH SRC_PROMPT DST_PROMPT # Local variables for this block

    # 验证密钥文件 (and exit if verification fails and user cancels)
    KEY_VERIFIED=true
    if [ "$SRC_AUTH_METHOD" = "1" ] && [ -n "$SRC_KEY_PATH" ]; then
        NEW_KEY_PATH=$(verify_key_path "$SRC_KEY_PATH" "源")
        if [ $? -ne 0 ]; then KEY_VERIFIED=false; else SRC_KEY_PATH="$NEW_KEY_PATH"; fi
    fi
    if [ "$KEY_VERIFIED" = true ] && [ "$DST_AUTH_METHOD" = "1" ] && [ -n "$DST_KEY_PATH" ]; then
        NEW_KEY_PATH=$(verify_key_path "$DST_KEY_PATH" "目标")
         if [ $? -ne 0 ]; then KEY_VERIFIED=false; else DST_KEY_PATH="$NEW_KEY_PATH"; fi
    fi

    if [ "$KEY_VERIFIED" = false ]; then
        echo "密钥验证失败，无法继续。" >&2
        exit 1
    fi


    # 检查路径是否为空 (仅当使用配置文件时才检查)
    if [ -z "$SRC_PATH" ]; then
        echo "从配置加载：源路径为空，需要手动输入。" >&2
        case $TRANSFER_TYPE in
            local_to_remote) SRC_PROMPT="源(本地)" ;;
            *) SRC_PROMPT="源(远程)" ;;
        esac
        SRC_PATH=$(get_path_info "$SRC_PROMPT" "") # Prompt without default
        if [ $? -ne 0 ]; then exit 1; fi
    fi

    if [ -z "$DST_PATH" ]; then
         echo "从配置加载：目标路径为空，需要手动输入。" >&2
        case $TRANSFER_TYPE in
            remote_to_local) DST_PROMPT="目标(本地)" ;;
            *) DST_PROMPT="目标(远程)" ;;
        esac
        DST_PATH=$(get_path_info "$DST_PROMPT" "") # Prompt without default
        if [ $? -ne 0 ]; then exit 1; fi
    fi
fi

# 显示传输任务摘要
echo
echo "传输任务摘要:"
echo "------------------------"
case $TRANSFER_TYPE in
    local_to_remote)
        echo "传输类型: 本地到服务器"
        echo "源路径 (本地): $SRC_PATH"
        echo "目标服务器: $DST_USER@$DST_SERVER:$DST_SSH_PORT"
        echo "目标路径: $DST_PATH"
        echo "认证方式: $([ "$DST_AUTH_METHOD" = "1" ] && echo "SSH密钥" || echo "密码")"
        if [ "$DST_AUTH_METHOD" = "1" ]; then
            echo "密钥路径: $DST_KEY_PATH"
        fi
        ;;

    remote_to_local)
        echo "传输类型: 服务器到本地"
        echo "源服务器: $SRC_USER@$SRC_SERVER:$SRC_SSH_PORT"
        echo "源路径: $SRC_PATH"
        echo "目标路径 (本地): $DST_PATH"
        echo "认证方式: $([ "$SRC_AUTH_METHOD" = "1" ] && echo "SSH密钥" || echo "密码")"
        if [ "$SRC_AUTH_METHOD" = "1" ]; then
            echo "密钥路径: $SRC_KEY_PATH"
        fi
        ;;

    remote_to_remote)
        echo "传输类型: 服务器到服务器"
        echo "源服务器: $SRC_USER@$SRC_SERVER:$SRC_SSH_PORT"
        echo "源路径: $SRC_PATH"
        echo "源认证方式: $([ "$SRC_AUTH_METHOD" = "1" ] && echo "SSH密钥" || echo "密码")"
        if [ "$SRC_AUTH_METHOD" = "1" ]; then
            echo "源密钥路径: $SRC_KEY_PATH"
        fi
        echo "目标服务器: $DST_USER@$DST_SERVER:$DST_SSH_PORT"
        echo "目标路径: $DST_PATH"
        echo "目标认证方式: $([ "$DST_AUTH_METHOD" = "1" ] && echo "SSH密钥" || echo "密码")"
        if [ "$DST_AUTH_METHOD" = "1" ]; then
            echo "目标密钥路径: $DST_KEY_PATH"
        fi
        ;;
    *)
        echo "错误：无效的传输类型 '$TRANSFER_TYPE' 无法显示摘要。" >&2
        exit 1
        ;;
esac
echo "------------------------"

# 确认传输
local CONFIRM # Make variable local
read -p "确认开始传输? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "传输已取消。" >&2
    exit 0
fi

# 执行传输
perform_transfer
TRANSFER_RESULT=$?

# 传输完成，询问是否保存配置
if [ $TRANSFER_RESULT -eq 0 ]; then # Only offer save on success
    if [ "$MANUAL_CONFIG" = true ]; then # Only ask if it was a manual config run
        local SAVE_CONFIG PROFILE_NAME_INPUT SAVED_SRC_PASSWORD SAVED_DST_PASSWORD CONFIG_LINE # Local vars
        read -p "传输成功！是否保存此配置到配置文件? (y/n): " SAVE_CONFIG
        if [ "$SAVE_CONFIG" = "y" ] || [ "$SAVE_CONFIG" = "Y" ]; then
            # Ensure PROFILE_NAME is asked for (it was reset earlier)
             PROFILE_NAME_INPUT="" # Initialize
             while [ -z "$PROFILE_NAME_INPUT" ]; do
                 read -p "请输入配置名称(用于标识): " PROFILE_NAME_INPUT
                 # Optional: Check if name already exists?
             done
             PROFILE_NAME="$PROFILE_NAME_INPUT" # Assign to the main variable

             # Prepare password fields for saving (save empty for security)
             SAVED_SRC_PASSWORD=""
             SAVED_DST_PASSWORD=""
             if [ "$SRC_AUTH_METHOD" = "2" ]; then
                 echo "警告：出于安全考虑，源密码不会保存到配置文件中。" >&2
             fi
             if [ "$DST_AUTH_METHOD" = "2" ]; then
                  if [ "$SRC_AUTH_METHOD" != "2" ]; then # Avoid duplicate warnings
                     echo "警告：出于安全考虑，目标密码不会保存到配置文件中。" >&2
                 fi
             fi
             # NOTE: Key paths ($SRC_KEY_PATH, $DST_KEY_PATH) ARE saved.

            # Build the config line using current variables
            # Ensure all variables are correctly populated before this point
            CONFIG_LINE="$PROFILE_NAME|$TRANSFER_TYPE|$SRC_SERVER|$SRC_SSH_PORT|$SRC_USER|$SRC_AUTH_METHOD|$SRC_KEY_PATH|$SAVED_SRC_PASSWORD|$SRC_PATH|$DST_SERVER|$DST_SSH_PORT|$DST_USER|$DST_AUTH_METHOD|$DST_KEY_PATH|$SAVED_DST_PASSWORD|$DST_PATH"

            # Append to the config file
            # The 'echo' command automatically adds a newline (\n) at the end,
            # ensuring each configuration is saved on its own line.
            echo "$CONFIG_LINE" >> "$CONFIG_FILE"
            if [ $? -eq 0 ]; then
                echo "配置 '$PROFILE_NAME' 已保存到 $CONFIG_FILE (密码字段已清空)。"
            else
                 echo "错误：无法写入配置文件 $CONFIG_FILE" >&2
            fi
        fi
    fi
fi

exit $TRANSFER_RESULT