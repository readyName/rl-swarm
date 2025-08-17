#!/bin/bash

# 柔和色彩设置
GREEN='\033[1;32m'      # 柔和绿色
BLUE='\033[1;36m'       # 柔和蓝色
RED='\033[1;31m'        # 柔和红色
YELLOW='\033[1;33m'     # 柔和黄色
NC='\033[0m'            # 无颜色

# 日志文件设置
LOG_FILE="$HOME/nexus.log"
MAX_LOG_SIZE=10485760 # 10MB，日志大小限制

# 检测操作系统
OS=$(uname -s)
case "$OS" in
  Darwin) OS_TYPE="macOS" ;;
  Linux)
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      if [[ "$ID" == "ubuntu" ]]; then
        OS_TYPE="Ubuntu"
      else
        OS_TYPE="Linux"
      fi
    else
      OS_TYPE="Linux"
    fi
    ;;
  *) echo -e "${RED}不支持的操作系统: $OS。本脚本仅支持 macOS 和 Ubuntu。${NC}" ; exit 1 ;;
esac

# 检测 shell 并设置配置文件
if [[ -n "$ZSH_VERSION" ]]; then
  SHELL_TYPE="zsh"
  CONFIG_FILE="$HOME/.zshrc"
elif [[ -n "$BASH_VERSION" ]]; then
  SHELL_TYPE="bash"
  CONFIG_FILE="$HOME/.bashrc"
else
  echo -e "${RED}不支持的 shell。本脚本仅支持 bash 和 zsh。${NC}"
  exit 1
fi

# 打印标题
print_header() {
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}=====================================${NC}"
}

# 检查命令是否存在
check_command() {
  if command -v "$1" &> /dev/null; then
    echo -e "${GREEN}$1 已安装，跳过安装步骤。${NC}"
    return 0
  else
    echo -e "${RED}$1 未安装，开始安装...${NC}"
    return 1
  fi
}

# 配置 shell 环境变量，避免重复写入
configure_shell() {
  local env_path="$1"
  local env_var="export PATH=$env_path:\$PATH"
  if [[ -f "$CONFIG_FILE" ]] && grep -Fx "$env_var" "$CONFIG_FILE" > /dev/null; then
    echo -e "${GREEN}环境变量已在 $CONFIG_FILE 中配置。${NC}"
  else
    echo -e "${BLUE}正在将环境变量添加到 $CONFIG_FILE...${NC}"
    echo "$env_var" >> "$CONFIG_FILE"
    echo -e "${GREEN}环境变量已添加到 $CONFIG_FILE。${NC}"
    # 应用当前会话的更改
    source "$CONFIG_FILE" 2>/dev/null || echo -e "${RED}无法加载 $CONFIG_FILE，请手动运行 'source $CONFIG_FILE'。${NC}"
  fi
}

# 日志轮转
rotate_log() {
  if [[ -f "$LOG_FILE" ]]; then
    if [[ "$OS_TYPE" == "macOS" ]]; then
      FILE_SIZE=$(stat -f %z "$LOG_FILE" 2>/dev/null)
    else
      FILE_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null)
    fi
    if [[ $FILE_SIZE -ge $MAX_LOG_SIZE ]]; then
      mv "$LOG_FILE" "${LOG_FILE}.$(date +%F_%H-%M-%S).bak"
      echo -e "${YELLOW}日志文件已轮转，新日志将写入 $LOG_FILE${NC}"
    fi
  fi
}

# 安装 Homebrew（macOS 和非 Ubuntu Linux）
install_homebrew() {
  print_header "检查 Homebrew 安装"
  if check_command brew; then
    return
  fi
  echo -e "${BLUE}在 $OS_TYPE 上安装 Homebrew...${NC}"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
    echo -e "${RED}安装 Homebrew 失败，请检查网络连接或权限。${NC}"
    exit 1
  }
  if [[ "$OS_TYPE" == "macOS" ]]; then
    configure_shell "/opt/homebrew/bin"
  else
    configure_shell "$HOME/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/bin"
    if ! check_command gcc; then
      echo -e "${BLUE}在 Linux 上安装 gcc（Homebrew 依赖）...${NC}"
      if command -v yum &> /dev/null; then
        sudo yum groupinstall 'Development Tools' || {
          echo -e "${RED}安装 gcc 失败，请手动安装 Development Tools。${NC}"
          exit 1
        }
      else
        echo -e "${RED}不支持的包管理器，请手动安装 gcc。${NC}"
        exit 1
      fi
    fi
  fi
}

# 安装基础依赖（仅 Ubuntu）
install_dependencies() {
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    print_header "安装基础依赖工具"
    echo -e "${BLUE}更新 apt 包索引并安装必要工具...${NC}"
    sudo apt-get update -y
    sudo apt-get install -y curl jq screen build-essential || {
      echo -e "${RED}安装依赖工具失败，请检查网络连接或权限。${NC}"
      exit 1
    }
  fi
}

# 安装 CMake
install_cmake() {
  print_header "检查 CMake 安装"
  if check_command cmake; then
    return
  fi
  echo -e "${BLUE}正在安装 CMake...${NC}"
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    sudo apt-get install -y cmake || {
      echo -e "${RED}安装 CMake 失败，请检查网络连接或权限。${NC}"
      exit 1
    }
  else
    brew install cmake || {
      echo -e "${RED}安装 CMake 失败，请检查 Homebrew 安装。${NC}"
      exit 1
    }
  fi
}

# 安装 Protobuf
install_protobuf() {
  print_header "检查 Protobuf 安装"
  if check_command protoc; then
    return
  fi
  echo -e "${BLUE}正在安装 Protobuf...${NC}"
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    sudo apt-get install -y protobuf-compiler || {
      echo -e "${RED}安装 Protobuf 失败，请检查网络连接或权限。${NC}"
      exit 1
    }
  else
    brew install protobuf || {
      echo -e "${RED}安装 Protobuf 失败，请检查 Homebrew 安装。${NC}"
      exit 1
    }
  fi
}

# 安装 Rust
install_rust() {
  print_header "检查 Rust 安装"
  if check_command rustc; then
    return
  fi
  echo -e "${BLUE}正在安装 Rust...${NC}"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || {
    echo -e "${RED}安装 Rust 失败，请检查网络连接。${NC}"
    exit 1
  }
  source "$HOME/.cargo/env" 2>/dev/null || echo -e "${RED}无法加载 Rust 环境，请手动运行 'source ~/.cargo/env'。${NC}"
  configure_shell "$HOME/.cargo/bin"
}

# 配置 Rust RISC-V 目标
configure_rust_target() {
  print_header "检查 Rust RISC-V 目标"
  if rustup target list --installed | grep -q "riscv32i-unknown-none-elf"; then
    echo -e "${GREEN}RISC-V 目标 (riscv32i-unknown-none-elf) 已安装，跳过。${NC}"
    return
  fi
  echo -e "${BLUE}为 Rust 添加 RISC-V 目标...${NC}"
  rustup target add riscv32i-unknown-none-elf || {
    echo -e "${RED}添加 RISC-V 目标失败，请检查 Rust 安装。${NC}"
    exit 1
  }
}

# 日志函数
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1" | tee -a "$LOG_FILE"
  rotate_log
}

# 退出时的清理函数
cleanup_exit() {
  log "${YELLOW}收到退出信号，正在清理 Nexus 节点进程...${NC}"
  
  if [[ "$OS_TYPE" == "macOS" ]]; then
    # macOS: 先获取窗口信息，再终止进程，最后关闭窗口
    log "${BLUE}正在获取 Nexus 相关窗口信息...${NC}"
    
    # 先识别并记录相关窗口的编号（在进程终止前）
    local window_ids=()
    local all_windows=$(osascript -e 'tell application "Terminal" to get id of every window' 2>/dev/null || echo "")
    
    if [[ -n "$all_windows" ]]; then
      log "${BLUE}当前所有终端窗口编号: $all_windows${NC}"
      
      # 获取所有窗口的详细信息（编号和名称）
      local window_info=$(osascript -e 'tell application "Terminal" to get {id, name} of every window' 2>/dev/null || echo "")
      
      # 获取当前终端的窗口ID（保护当前终端不被关闭）
      local current_window_id=$(osascript -e 'tell app "Terminal" to id of front window' 2>/dev/null || echo "")
      log "${BLUE}当前终端窗口ID: $current_window_id（将被保护）${NC}"
      
      # 查找可能包含 Nexus 相关内容的窗口
      # 将逗号分隔的窗口ID转换为数组
      IFS=',' read -ra window_array <<< "$all_windows"
      
      for window_id in "${window_array[@]}"; do
        # 清理窗口ID，移除空格
        window_id=$(echo "$window_id" | tr -d ' ')
        
        # 跳过空的窗口ID
        [[ -z "$window_id" ]] && continue
        
        # 获取该窗口的名称
        local window_name=$(osascript -e 'tell application "Terminal" to get name of window id '"$window_id" 2>/dev/null || echo "")
        
        if [[ -n "$window_name" ]]; then
          # 检查窗口名称是否包含相关关键词
          if [[ "$window_name" =~ nexus ]] || \
             [[ "$window_name" =~ "nexus-network" ]] || \
             [[ "$window_name" =~ "nexus-cli" ]]; then
            
            # 确保不关闭当前终端窗口
            if [[ "$window_id" != "$current_window_id" ]]; then
              window_ids+=("$window_id")
              log "${BLUE}发现 Nexus 相关窗口: ID=$window_id${NC}"
            fi
          fi
        fi
      done
    fi
    
    # 现在终止进程
    log "${BLUE}正在终止 Nexus 节点进程...${NC}"
    
    # 查找并终止 nexus-network 和 nexus-cli 进程
    local pids=$(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ')
    if [[ -n "$pids" ]]; then
      log "${BLUE}发现进程: $pids，正在终止...${NC}"
      for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null || true
        sleep 1
        # 如果进程还在运行，强制终止
        if ps -p "$pid" > /dev/null 2>&1; then
          kill -KILL "$pid" 2>/dev/null || true
        fi
      done
    fi
    
    # 等待进程完全终止
    sleep 2
    
    # 清理 screen 会话（如果存在）
    if screen -list | grep -q "nexus_node"; then
      log "${BLUE}正在终止 nexus_node screen 会话...${NC}"
      screen -S nexus_node -X quit 2>/dev/null || log "${RED}无法终止 screen 会话，请检查权限或会话状态。${NC}"
    fi
  else
    # 非 macOS: 清理 screen 会话
    if screen -list | grep -q "nexus_node"; then
      log "${BLUE}正在终止 nexus_node screen 会话...${NC}"
      screen -S nexus_node -X quit 2>/dev/null || log "${RED}无法终止 screen 会话，请检查权限或会话状态。${NC}"
    fi
  fi
  
  # 查找并终止 nexus-network 和 nexus-cli 进程
  log "${BLUE}正在查找并清理残留的 Nexus 进程...${NC}"
  PIDS=$(ps aux | grep -E "nexus-cli|nexus-network" | grep -v grep | awk '{print $2}' | tr '\n' ' ' | xargs echo -n)
  log "${BLUE}ps 找到的进程: '$PIDS'${NC}"
  
  if [[ -z "$PIDS" ]]; then
    log "${YELLOW}ps 未找到进程，尝试 pgrep...${NC}"
    PIDS=$(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ' | xargs echo -n)
    log "${BLUE}pgrep 找到的进程: '$PIDS'${NC}"
  fi
  
  if [[ -n "$PIDS" ]]; then
    for pid in $PIDS; do
      if ps -p "$pid" > /dev/null 2>&1; then
        log "${BLUE}正在终止 Nexus 节点进程 (PID: $pid)...${NC}"
        kill -9 "$pid" 2>/dev/null || log "${RED}无法终止 PID $pid 的进程，请检查进程状态。${NC}"
      fi
    done
  else
    log "${GREEN}未找到残留的 nexus-network 或 nexus-cli 进程。${NC}"
  fi
  
  # 额外清理：查找可能的子进程
  log "${BLUE}检查是否有子进程残留...${NC}"
  local child_pids=$(pgrep -P $(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ') 2>/dev/null | tr '\n' ' ')
  if [[ -n "$child_pids" ]]; then
    log "${BLUE}发现子进程: $child_pids，正在清理...${NC}"
    for pid in $child_pids; do
      kill -9 "$pid" 2>/dev/null || true
    done
  fi
  
  # 等待所有进程完全清理
  sleep 3
  
  # 最后才关闭窗口（确保所有进程都已终止）
  if [[ "$OS_TYPE" == "macOS" ]]; then
    log "${BLUE}正在关闭 Nexus 节点终端窗口...${NC}"
    
    # 使用之前保存的窗口ID关闭窗口
    if [[ ${#window_ids[@]} -gt 0 ]]; then
      log "${BLUE}检测到需要关闭的目标窗口ID: ${window_ids[*]}${NC}"
      log "${BLUE}正在关闭之前识别的 ${#window_ids[@]} 个 Nexus 相关窗口...${NC}"
      
      for window_id in "${window_ids[@]}"; do
        log "${BLUE}正在关闭窗口 ID: $window_id${NC}"
        osascript -e "tell application \"Terminal\" to close window id $window_id saving no" 2>/dev/null || true
      done
      
      sleep 10
      log "${BLUE}窗口关闭完成，等待10秒后继续...${NC}"
      
      # 验证窗口是否已关闭
      local remaining_windows=$(osascript -e 'tell application "Terminal" to get name of every window' 2>/dev/null || echo "")
      log "${BLUE}关闭后剩余窗口: $remaining_windows${NC}"
    else
      log "${YELLOW}未找到 Nexus 相关窗口，使用备用方案...${NC}"
      # 备用方案：使用通用关键词关闭
      osascript -e 'tell application "Terminal" to close (every window whose name contains "nexus")' 2>/dev/null || true
      osascript -e 'tell application "Terminal" to close (every window whose name contains "nexus-network")' 2>/dev/null || true
      osascript -e 'tell application "Terminal" to close (every window whose name contains "nexus-cli")' 2>/dev/null || true
    fi
  fi
  
  log "${GREEN}清理完成，脚本退出。${NC}"
  exit 0
}

# 重启时的清理函数
cleanup_restart() {
  # 重启前清理日志
  if [[ -f "$LOG_FILE" ]]; then
    rm -f "$LOG_FILE"
    echo -e "${YELLOW}已清理旧日志文件 $LOG_FILE${NC}"
  fi
  log "${YELLOW}准备重启节点，开始清理流程...${NC}"
  
  if [[ "$OS_TYPE" == "macOS" ]]; then
    # macOS: 先获取窗口信息，再终止进程，最后关闭窗口
    log "${BLUE}正在获取 Nexus 相关窗口信息...${NC}"
    
    # 先识别并记录相关窗口的编号（在进程终止前）
    local window_ids=()
    local all_windows=$(osascript -e 'tell application "Terminal" to get id of every window' 2>/dev/null || echo "")
    
    if [[ -n "$all_windows" ]]; then
      log "${BLUE}当前所有终端窗口编号: $all_windows${NC}"
      
      # 获取所有窗口的详细信息（编号和名称）
      local window_info=$(osascript -e 'tell application "Terminal" to get {id, name} of every window' 2>/dev/null || echo "")
      
      # 获取当前终端的窗口ID（保护当前终端不被关闭）
      local current_window_id=$(osascript -e 'tell app "Terminal" to id of front window' 2>/dev/null || echo "")
      log "${BLUE}当前终端窗口ID: $current_window_id（将被保护）${NC}"
      
      # 查找可能包含 Nexus 相关内容的窗口
      # 将逗号分隔的窗口ID转换为数组
      IFS=',' read -ra window_array <<< "$all_windows"
      
      for window_id in "${window_array[@]}"; do
        # 清理窗口ID，移除空格
        window_id=$(echo "$window_id" | tr -d ' ')
        
        # 跳过空的窗口ID
        [[ -z "$window_id" ]] && continue
        
        # 获取该窗口的名称
        local window_name=$(osascript -e 'tell application "Terminal" to get name of window id '"$window_id" 2>/dev/null || echo "")
        
        if [[ -n "$window_name" ]]; then
          log "${BLUE}窗口 $window_id 名称: $window_name${NC}"
          
          # 检查窗口名称是否包含相关关键词
          if [[ "$window_name" =~ nexus ]] || \
             [[ "$window_name" =~ "nexus-network" ]] || \
             [[ "$window_name" =~ "nexus-cli" ]]; then
            
            # 确保不关闭当前终端窗口
            if [[ "$window_id" != "$current_window_id" ]]; then
              window_ids+=("$window_id")
              log "${BLUE}发现相关窗口: ID=$window_id, 名称=$window_name${NC}"
            else
              log "${BLUE}跳过当前终端窗口: ID=$window_id${NC}"
            fi
          fi
        fi
      done
    fi
    
    # 现在终止进程
    log "${BLUE}正在终止 Nexus 节点进程...${NC}"
    
    # 查找并终止 nexus-network 和 nexus-cli 进程
    local pids=$(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ')
    if [[ -n "$pids" ]]; then
      log "${BLUE}发现进程: $pids，正在终止...${NC}"
      for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null || true
        sleep 1
        # 如果进程还在运行，强制终止
        if ps -p "$pid" > /dev/null 2>&1; then
          kill -KILL "$pid" 2>/dev/null || true
        fi
      done
    fi
    
    # 等待进程完全终止
    sleep 2
    
    # 清理 screen 会话（如果存在）
    if screen -list | grep -q "nexus_node"; then
      log "${BLUE}正在终止 nexus_node screen 会话...${NC}"
      screen -S nexus_node -X quit 2>/dev/null || log "${RED}无法终止 screen 会话，请检查权限或会话状态。${NC}"
    fi
  else
    # 非 macOS: 清理 screen 会话
    if screen -list | grep -q "nexus_node"; then
      log "${BLUE}正在终止 nexus_node screen 会话...${NC}"
      screen -S nexus_node -X quit 2>/dev/null || log "${RED}无法终止 screen 会话，请检查权限或会话状态。${NC}"
    fi
  fi
  
  # 查找并终止 nexus-network 和 nexus-cli 进程
  log "${BLUE}正在查找并清理残留的 Nexus 进程...${NC}"
  PIDS=$(ps aux | grep -E "nexus-cli|nexus-network" | grep -v grep | awk '{print $2}' | tr '\n' ' ' | xargs echo -n)
  log "${BLUE}ps 找到的进程: '$PIDS'${NC}"
  
  if [[ -z "$PIDS" ]]; then
    log "${YELLOW}ps 未找到进程，尝试 pgrep...${NC}"
    PIDS=$(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ' | xargs echo -n)
    log "${BLUE}pgrep 找到的进程: '$PIDS'${NC}"
  fi
  
  if [[ -n "$PIDS" ]]; then
    for pid in $PIDS; do
      if ps -p "$pid" > /dev/null 2>&1; then
        log "${BLUE}正在终止 Nexus 节点进程 (PID: $pid)...${NC}"
        kill -9 "$pid" 2>/dev/null || log "${RED}无法终止 PID $pid 的进程，请检查进程状态。${NC}"
      fi
    done
  else
    log "${GREEN}未找到残留的 nexus-network 或 nexus-cli 进程。${NC}"
  fi
  
  # 额外清理：查找可能的子进程
  log "${BLUE}检查是否有子进程残留...${NC}"
  local child_pids=$(pgrep -P $(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ') 2>/dev/null | tr '\n' ' ')
  if [[ -n "$child_pids" ]]; then
    log "${BLUE}发现子进程: $child_pids，正在清理...${NC}"
    for pid in $child_pids; do
      kill -9 "$pid" 2>/dev/null || true
    done
  fi
  
  # 等待所有进程完全清理
  sleep 3
  
  # 最后才关闭窗口（确保所有进程都已终止）
  if [[ "$OS_TYPE" == "macOS" ]]; then
    log "${BLUE}正在关闭 Nexus 节点终端窗口...${NC}"
    
    # 使用之前保存的窗口ID关闭窗口
    if [[ ${#window_ids[@]} -gt 0 ]]; then
      log "${BLUE}检测到需要关闭的目标窗口ID: ${window_ids[*]}${NC}"
      log "${BLUE}正在关闭之前识别的 ${#window_ids[@]} 个 Nexus 相关窗口...${NC}"
      
      for window_id in "${window_ids[@]}"; do
        log "${BLUE}正在关闭窗口 ID: $window_id${NC}"
        osascript -e "tell application \"Terminal\" to close window id $window_id saving no" 2>/dev/null || true
      done
      
      sleep 10
      log "${BLUE}窗口关闭完成，等待10秒后继续...${NC}"
      
      # 验证窗口是否已关闭
      local remaining_windows=$(osascript -e 'tell application "Terminal" to get name of every window' 2>/dev/null || echo "")
      log "${BLUE}关闭后剩余窗口: $remaining_windows${NC}"
    else
      log "${YELLOW}未找到 Nexus 相关窗口，使用备用方案...${NC}"
      # 备用方案：使用通用关键词关闭
      osascript -e 'tell application "Terminal" to close (every window whose name contains "nexus")' 2>/dev/null || true
      osascript -e 'tell application "Terminal" to close (every window whose name contains "nexus-network")' 2>/dev/null || true
      osascript -e 'tell application "Terminal" to close (every window whose name contains "nexus-cli")' 2>/dev/null || true
    fi
  fi
  
  log "${GREEN}清理完成，准备重启节点。${NC}"
}

trap 'cleanup_exit' SIGINT SIGTERM SIGHUP

# 安装或更新 Nexus CLI
install_nexus_cli() {
  local attempt=1
  local max_attempts=3
  local success=false
  while [[ $attempt -le $max_attempts ]]; do
    log "${BLUE}正在安装/更新 Nexus CLI（第 $attempt/$max_attempts 次）...${NC}"
    if curl -s https://cli.nexus.xyz/ | sh &>/dev/null; then
      log "${GREEN}Nexus CLI 安装/更新成功！${NC}"
      success=true
      break
    else
      log "${YELLOW}第 $attempt 次安装/更新 Nexus CLI 失败。${NC}"
      ((attempt++))
      sleep 2
    fi
  done
  # 确保配置文件存在，如果没有就生成并写入 PATH 变量
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "export PATH=\"$HOME/.cargo/bin:\$PATH\"" > "$CONFIG_FILE"
    log "${YELLOW}未检测到 $CONFIG_FILE，已自动生成并写入 PATH 变量。${NC}"
  fi
  # 更新CLI后加载环境变量
  source "$CONFIG_FILE" 2>/dev/null && log "${GREEN}已自动加载 $CONFIG_FILE 环境变量。${NC}" || log "${YELLOW}未能自动加载 $CONFIG_FILE，请手动执行 source $CONFIG_FILE。${NC}"
  # 额外加载.zshrc确保环境变量生效
  if [[ -f "$HOME/.zshrc" ]]; then
    source "$HOME/.zshrc" 2>/dev/null && log "${GREEN}已额外加载 ~/.zshrc 环境变量。${NC}" || log "${YELLOW}未能加载 ~/.zshrc，请手动执行 source ~/.zshrc。${NC}"
  fi
  if [[ "$success" == false ]]; then
    log "${RED}Nexus CLI 安装/更新失败 $max_attempts 次，将尝试使用当前版本运行节点。${NC}"
  fi
  if command -v nexus-network &>/dev/null; then
    log "${GREEN}nexus-network 版本：$(nexus-network --version 2>/dev/null)${NC}"
  elif command -v nexus-cli &>/dev/null; then
    log "${GREEN}nexus-cli 版本：$(nexus-cli --version 2>/dev/null)${NC}"
  else
    log "${RED}未找到 nexus-network 或 nexus-cli，无法运行节点。${NC}"
    exit 1
  fi
  
  # 首次安装后生成仓库hash，避免首次运行时等待
  if [[ ! -f "$HOME/.nexus/last_commit" ]]; then
    log "${BLUE}首次安装，正在生成仓库hash记录...${NC}"
    local repo_url="https://github.com/nexus-xyz/nexus-cli.git"
    local current_commit=$(git ls-remote --heads "$repo_url" main 2>/dev/null | cut -f1)
    
    if [[ -n "$current_commit" ]]; then
      mkdir -p "$HOME/.nexus"
      echo "$current_commit" > "$HOME/.nexus/last_commit"
      log "${GREEN}已记录当前仓库版本: ${current_commit:0:8}${NC}"
    else
      log "${YELLOW}无法获取仓库信息，将在后续检测时创建${NC}"
    fi
  fi
}

# 读取或设置 Node ID，添加 5 秒超时
get_node_id() {
  CONFIG_PATH="$HOME/.nexus/config.json"
  if [[ -f "$CONFIG_PATH" ]]; then
    CURRENT_NODE_ID=$(jq -r .node_id "$CONFIG_PATH" 2>/dev/null)
    if [[ -n "$CURRENT_NODE_ID" && "$CURRENT_NODE_ID" != "null" ]]; then
      log "${GREEN}检测到配置文件中的 Node ID：$CURRENT_NODE_ID${NC}"
      # 使用 read -t 5 实现 5 秒超时，默认选择 y
      echo -e "${BLUE}是否使用此 Node ID? (y/n, 默认 y，5 秒后自动继续): ${NC}"
      use_old_id=""
      read -t 5 -r use_old_id
      use_old_id=${use_old_id:-y} # 默认 y
      if [[ "$use_old_id" =~ ^[Nn]$ ]]; then
        read -rp "请输入新的 Node ID: " NODE_ID_TO_USE
        # 验证 Node ID（假设需要非空且只包含字母、数字、连字符）
        if [[ -z "$NODE_ID_TO_USE" || ! "$NODE_ID_TO_USE" =~ ^[a-zA-Z0-9-]+$ ]]; then
          log "${RED}无效的 Node ID，请输入只包含字母、数字或连字符的 ID。${NC}"
          exit 1
        fi
        jq --arg id "$NODE_ID_TO_USE" '.node_id = $id' "$CONFIG_PATH" > "$CONFIG_PATH.tmp" && mv "$CONFIG_PATH.tmp" "$CONFIG_PATH"
        log "${GREEN}已更新 Node ID: $NODE_ID_TO_USE${NC}"
      else
        NODE_ID_TO_USE="$CURRENT_NODE_ID"
      fi
    else
      log "${YELLOW}未检测到有效 Node ID，请输入新的 Node ID。${NC}"
      read -rp "请输入新的 Node ID: " NODE_ID_TO_USE
      if [[ -z "$NODE_ID_TO_USE" || ! "$NODE_ID_TO_USE" =~ ^[a-zA-Z0-9-]+$ ]]; then
        log "${RED}无效的 Node ID，请输入只包含字母、数字或连字符的 ID。${NC}"
        exit 1
      fi
      mkdir -p "$HOME/.nexus"
      echo "{\"node_id\": \"${NODE_ID_TO_USE}\"}" > "$CONFIG_PATH"
      log "${GREEN}已写入 Node ID: $NODE_ID_TO_USE 到 $CONFIG_PATH${NC}"
    fi
  else
    log "${YELLOW}未找到配置文件 $CONFIG_PATH，请输入 Node ID。${NC}"
    read -rp "请输入新的 Node ID: " NODE_ID_TO_USE
    if [[ -z "$NODE_ID_TO_USE" || ! "$NODE_ID_TO_USE" =~ ^[a-zA-Z0-9-]+$ ]]; then
      log "${RED}无效的 Node ID，请输入只包含字母、数字或连字符的 ID。${NC}"
      exit 1
    fi
    mkdir -p "$HOME/.nexus"
    echo "{\"node_id\": \"${NODE_ID_TO_USE}\"}" > "$CONFIG_PATH"
    log "${GREEN}已写入 Node ID: $NODE_ID_TO_USE 到 $CONFIG_PATH${NC}"
  fi
}

# 检测 GitHub 仓库更新
check_github_updates() {
  local repo_url="https://github.com/nexus-xyz/nexus-cli.git"
  log "${BLUE}检查 Nexus CLI 仓库更新...${NC}"
  
  # 获取远程仓库最新提交
  local current_commit=$(git ls-remote --heads "$repo_url" main 2>/dev/null | cut -f1)
  
  if [[ -z "$current_commit" ]]; then
    log "${YELLOW}无法获取远程仓库信息，跳过更新检测${NC}"
    return 1
  fi
  
  if [[ -f "$HOME/.nexus/last_commit" ]]; then
    local last_commit=$(cat "$HOME/.nexus/last_commit")
    if [[ "$current_commit" != "$last_commit" ]]; then
      log "${GREEN}检测到仓库更新！${NC}"
      log "${BLUE}上次提交: ${last_commit:0:8}${NC}"
      log "${BLUE}最新提交: ${current_commit:0:8}${NC}"
      echo "$current_commit" > "$HOME/.nexus/last_commit"
      return 0  # 有更新
    else
      log "${GREEN}仓库无更新，当前版本: ${current_commit:0:8}${NC}"
      return 1  # 无更新
    fi
  else
    log "${BLUE}首次运行，记录当前提交: ${current_commit:0:8}${NC}"
    echo "$current_commit" > "$HOME/.nexus/last_commit"
    return 0  # 首次运行
  fi
}

# 启动节点
start_node() {
  log "${BLUE}正在启动 Nexus 节点 (Node ID: $NODE_ID_TO_USE)...${NC}"
  rotate_log
  
  if [[ "$OS_TYPE" == "macOS" ]]; then
    # macOS: 新开终端窗口启动节点
    log "${BLUE}在 macOS 中打开新终端窗口启动节点...${NC}"
    osascript -e 'tell application "Terminal"
      set newWindow to do script "cd ~ && echo \"🚀 正在启动 Nexus 节点...\" && nexus-network start --node-id '"$NODE_ID_TO_USE"' && echo \"✅ 节点已启动，按任意键关闭窗口...\" && read -n 1"
      tell front window
        set number of columns to 109
        set number of rows to 32
      end tell
    end tell'
    
    # 等待一下确保窗口打开
    sleep 3
    
    # 检查是否有新终端窗口打开
    if pgrep -f "nexus-network start" > /dev/null; then
      log "${GREEN}Nexus 节点已在新终端窗口中启动${NC}"
    else
      log "${YELLOW}nexus-network 启动失败，尝试用 nexus-cli 启动...${NC}"
              osascript -e 'tell application "Terminal"
          set newWindow to do script "cd ~ && echo \"🚀 正在启动 Nexus 节点...\" && nexus-cli start --node-id '"$NODE_ID_TO_USE"' && echo \"✅ 节点已启动，按任意键关闭窗口...\" && read -n 1"
          tell front window
            set number of columns to 109
            set number of rows to 32
          end tell
        end tell'
      sleep 3
      
      if pgrep -f "nexus-cli start" > /dev/null; then
        log "${GREEN}Nexus 节点已通过 nexus-cli 在新终端窗口中启动${NC}"
      else
        log "${RED}启动失败，将在下次更新检测时重试${NC}"
        return 1
      fi
    fi
  else
    # 非 macOS: 使用 screen 启动（保持原有逻辑）
    log "${BLUE}在 $OS_TYPE 中使用 screen 启动节点...${NC}"
    screen -dmS nexus_node bash -c "nexus-network start --node-id '${NODE_ID_TO_USE}' >> $LOG_FILE 2>&1"
    sleep 2
    if screen -list | grep -q "nexus_node"; then
      log "${GREEN}Nexus 节点已在 screen 会话（nexus_node）中启动，日志输出到 $LOG_FILE${NC}"
    else
      log "${YELLOW}nexus-network 启动失败，尝试用 nexus-cli 启动...${NC}"
      screen -dmS nexus_node bash -c "nexus-cli start --node-id '${NODE_ID_TO_USE}' >> $LOG_FILE 2>&1"
      sleep 2
      if screen -list | grep -q "nexus_node"; then
        log "${GREEN}Nexus 节点已通过 nexus-cli 启动，日志输出到 $LOG_FILE${NC}"
      else
        log "${RED}启动失败，将在下次更新检测时重试${NC}"
        return 1
      fi
    fi
  fi
  
  return 0
}

# 主循环
main() {
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    install_dependencies
  fi
  if [[ "$OS_TYPE" == "macOS" || "$OS_TYPE" == "Linux" ]]; then
    install_homebrew
  fi
  install_cmake
  install_protobuf
  install_rust
  configure_rust_target
  get_node_id
  
  # 首次启动节点
  log "${BLUE}首次启动 Nexus 节点...${NC}"
  cleanup_restart
  install_nexus_cli
  if start_node; then
    log "${GREEN}节点启动成功！${NC}"
  else
    log "${YELLOW}节点启动失败，将在下次更新检测时重试${NC}"
  fi
  
  log "${BLUE}开始监控 GitHub 仓库更新...${NC}"
  log "${BLUE}检测频率：每30分钟检查一次${NC}"
  log "${BLUE}重启条件：仅在检测到仓库更新时重启${NC}"
  
  while true; do
    # 每30分钟检查一次更新
    sleep 1800
    
    if check_github_updates; then
      log "${BLUE}检测到更新，准备重启节点...${NC}"
      cleanup_restart
      install_nexus_cli
      if start_node; then
        log "${GREEN}节点已成功重启！${NC}"
      else
        log "${YELLOW}节点重启失败，将在下次更新检测时重试${NC}"
      fi
    else
      log "${BLUE}无更新，节点继续运行...${NC}"
    fi
  done
}

main