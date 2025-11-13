#!/bin/bash

# RL-Swarm version
RL_SWARM_VERSION="0.7.0"

export WANDB_MODE=disabled
export WANDB_MODE=offline
export WANDB_DISABLED=true
export WANDB_SILENT=true
export WANDB_CONSOLE=off

MAX_RETRIES=1000000
WARNING_THRESHOLD=10
RETRY_COUNT=0

# ====== 📝 带时间戳的日志函数 ======
log() {
  echo "【📅 $(date '+%Y-%m-%d %H:%M:%S')】 $1"
}

# ====== 🛑 处理 Ctrl+C 退出信号 ======
cleanup() {
  local mode=$1  # "exit" 或 "restart"
  log "🛑 触发清理流程（模式: $mode）..."
  # 杀主进程
  if [ -n "$RL_PID" ] && kill -0 "$RL_PID" 2>/dev/null; then
    log "🧨 杀死主进程 PID: $RL_PID"
    kill -9 "$RL_PID" 2>/dev/null
  fi
  # 杀子进程
  if [ -n "$PY_PID" ] && kill -0 "$PY_PID" 2>/dev/null; then
    log "⚔️ 杀死 Python 子进程 PID: $PY_PID"
    kill -9 "$PY_PID" 2>/dev/null
  fi
  # 释放端口 3000
  log "🌐 检查并释放端口 3000..."
  PORT_PID=$(lsof -ti:3000)
  if [ -n "$PORT_PID" ]; then
    log "⚠️ 端口 3000 被 PID $PORT_PID 占用，正在释放..."
    kill -9 "$PORT_PID" 2>/dev/null
    log "✅ 端口 3000 已释放"
  else
    log "✅ 端口 3000 已空闲"
  fi
  # 清理所有相关 python 进程
  log "🧨 清理所有相关 python 进程..."
  pgrep -f "python.*swarm_launcher" | while read pid; do
    log "⚔️ 杀死 python.swarm_launcher 进程 PID: $pid"
    kill -9 "$pid" 2>/dev/null || true
  done
  pgrep -f "python.*run_rl_swarm" | while read pid; do
    log "⚔️ 杀死 python.run_rl_swarm 进程 PID: $pid"
    kill -9 "$pid" 2>/dev/null || true
  done
  pgrep -af python | grep Resources | awk '{print $1}' | while read pid; do
    log "⚔️ 杀死 python+Resources 进程 PID: $pid"
    kill -9 "$pid" 2>/dev/null || true
  done
  log "🛑 清理完成"
  if [ "$mode" = "exit" ]; then
    exit 0
  fi
}

# 绑定 Ctrl+C 信号到 cleanup 函数（退出模式）
trap 'cleanup exit' SIGINT


# ====== 重建虚拟环境函数 ======
rebuild_venv() {
  local current_dir=$(pwd)
  log "🔧 开始重建虚拟环境... (当前目录: $current_dir)"
  
  # 如果虚拟环境存在，先删除
  if [ -d ".venv" ]; then
    log "🗑️ 删除现有虚拟环境 .venv..."
    if rm -rf .venv; then
      log "✅ 虚拟环境已删除"
    else
      log "⚠️ 删除虚拟环境失败，但继续尝试重建"
    fi
  else
    log "ℹ️ 虚拟环境不存在，直接创建新环境"
  fi
  
  # 确定 Python 命令
  local PYTHON_CMD=""
  if command -v python3.10 >/dev/null 2>&1; then
    PYTHON_CMD=python3.10
    log "✅ 使用 Python 3.10"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD=python3
    log "✅ 使用 Python 3"
  else
    log "❌ 未找到 Python 3.10 或 python3，无法重建虚拟环境"
    return 1
  fi
  
  # 创建新的虚拟环境
  log "📦 正在创建新的虚拟环境..."
  if $PYTHON_CMD -m venv .venv 2>&1; then
    log "✅ 虚拟环境创建成功"
    
    # 激活虚拟环境并安装基础依赖
    log "📥 激活虚拟环境并安装基础依赖..."
    if [ -f ".venv/bin/activate" ]; then
      source .venv/bin/activate
      
      # 升级 pip
      log "⬆️ 升级 pip..."
      pip install --upgrade pip >/dev/null 2>&1 || log "⚠️ pip 升级失败，但继续执行"
      
      # 检查并安装 web3（gensyn.sh 中需要的依赖）
      if ! python -c "import web3" 2>/dev/null; then
        log "⚙️ 正在安装 web3..."
        pip install web3 >/dev/null 2>&1 || log "⚠️ web3 安装失败，但继续执行"
      else
        log "✅ web3 已存在，跳过安装"
      fi
      
      log "✅ 虚拟环境重建完成"
      return 0
    else
      log "❌ 虚拟环境激活脚本不存在"
      return 1
    fi
  else
    log "❌ 虚拟环境创建失败"
    return 1
  fi
}

# ====== 检查并更新代码函数 ======
check_and_update_code() {
  log "🔄 检查代码更新..."
  
  # 获取当前目录
  local current_dir=$(pwd)
  log "📁 当前工作目录: $current_dir"
  
  # 检查是否在 git 仓库中，如果不是则切换到 ~/rl-swarm 目录
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log "⚠️ 当前目录不是 git 仓库，切换到 ~/rl-swarm 目录"
    if [ -d "$HOME/rl-swarm" ]; then
      cd "$HOME/rl-swarm" 2>/dev/null || {
        log "⚠️ 无法切换到 ~/rl-swarm 目录，跳过代码更新检查"
        return 0
      }
      log "✅ 已切换到 ~/rl-swarm 目录: $(pwd)"
    else
      log "⚠️ ~/rl-swarm 目录不存在，跳过代码更新检查"
      return 0
    fi
  fi
  
  # 获取远程更新（设置超时和错误处理）
  log "🌐 获取远程仓库信息..."
  # 使用简单的超时机制
  if ! git fetch origin 2>/dev/null; then
    log "⚠️ 无法连接远程仓库，跳过代码更新检查"
    return 0
  fi
  
  # 检查是否有更新
  local current_branch=$(git branch --show-current 2>/dev/null)
  if [ -z "$current_branch" ]; then
    log "⚠️ 无法获取当前分支信息，跳过代码更新检查"
    return 0
  fi
  
  local remote_branch="origin/$current_branch"
  
  # 比较本地和远程分支
  local local_commit=$(git rev-parse HEAD 2>/dev/null)
  local remote_commit=$(git rev-parse $remote_branch 2>/dev/null)
  
  if [ -z "$local_commit" ] || [ -z "$remote_commit" ]; then
    log "⚠️ 无法获取提交信息，跳过代码更新检查"
    return 0
  fi
  
  if [ "$local_commit" = "$remote_commit" ]; then
    log "✅ 代码已是最新版本，无需更新"
    return 0
  fi
  
  # 有更新，执行 git pull
  log "🔄 检测到代码更新，正在拉取最新代码..."
  if git pull origin "$current_branch" 2>/dev/null; then
    log "✅ 代码更新成功！"
    log "📊 更新详情："
    log "   本地提交: ${local_commit:0:8}"
    log "   远程提交: ${remote_commit:0:8}"
    # 代码更新成功，重建虚拟环境
    log "🔄 准备重建虚拟环境..."
    if rebuild_venv; then
      log "✅ 虚拟环境重建流程完成"
    else
      log "⚠️ 虚拟环境重建失败，但继续执行"
    fi
    return 0
  else
    log "⚠️ git pull 失败，尝试强制更新..."
    log "🔄 执行 git fetch origin --prune..."
    if git fetch origin --prune 2>/dev/null; then
      log "✅ git fetch 成功，正在强制重置到远程分支..."
      if git reset --hard "origin/$current_branch" 2>/dev/null; then
        log "✅ 强制更新成功！"
        log "📊 强制更新详情："
        log "   本地提交: ${local_commit:0:8}"
        log "   远程提交: ${remote_commit:0:8}"
        log "   当前分支: $current_branch"
        # 代码更新成功，重建虚拟环境
        log "🔄 准备重建虚拟环境..."
        if rebuild_venv; then
          log "✅ 虚拟环境重建流程完成"
        else
          log "⚠️ 虚拟环境重建失败，但继续执行"
        fi
        return 0
      else
        log "⚠️ git reset --hard 失败，继续使用当前版本运行"
        return 0
      fi
    else
      log "⚠️ git fetch 失败，可能是网络问题，继续使用当前版本运行"
      return 0
    fi
  fi
}

# ====== Peer ID 查询并写入桌面函数 ======
query_and_save_peerid_info() {
  local peer_id="$1"
  local desktop_path=~/Desktop/peerid_info.txt
  local output
  output=$(.venv/bin/python ./gensyncheck.py "$peer_id" | tee -a "$desktop_path")
  if echo "$output" | grep -q "__NEED_RESTART__"; then
    log "⚠️ 超过4小时未有新交易，自动重启！"
    cleanup restart
  fi
  log "✅ 已尝试查询 Peer ID 合约参数，结果已追加写入桌面: $desktop_path"
}

# ====== 🔁 主循环：启动和监控 RL Swarm ======
log "🎯 RL-Swarm v${RL_SWARM_VERSION} 自动运行脚本已启动"

# 首次启动时检查代码更新
check_and_update_code

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  log "🚀 第 $((RETRY_COUNT + 1)) 次尝试：启动 RL Swarm v${RL_SWARM_VERSION}..."

  # ✅ 设置 MPS 环境（适用于 Mac M1/M2）
  export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
  export PYTORCH_ENABLE_MPS_FALLBACK=1
  source ~/.zshrc 2>/dev/null || true

  # ✅ 检查并杀死残留的 p2pd 进程
  if pgrep -x "p2pd" >/dev/null; then
    log "🔍 发现残留的 p2pd 进程，正在终止..."
    pkill -9 p2pd
    log "✅ p2pd 进程已终止"
  fi

  # ✅ 在后台启动主脚本并自动输入空值
  WANDB_MODE=disabled ./run_rl_swarm.sh &
  RL_PID=$!

  # ✅ 循环检测 Python 子进程初始化
  sleep 300
  PY_PID=$(pgrep -P $RL_PID -f python | head -n 1)

  if [ -z "$PY_PID" ]; then
    log "⚠️ 未找到 Python 子进程，将监控 RL_PID: $RL_PID 替代 PY_PID"
  else
    log "✅ 检测到 Python 子进程，PID: $PY_PID"
  fi

  # ====== 检测并保存 Peer ID ======
  PEERID_LOG="logs/swarm_launcher.log"
  PEERID_FILE="peerid.txt"
  # 启动时不再主动检测和保存 PeerID，延后到定时任务中

  # ✅ 监控进程（根据 PY_PID 是否存在选择 RL_PID 或 PY_PID）
  DISK_LIMIT_GB=20
  MEM_CHECK_INTERVAL=600
  MEM_CHECK_TIMER=0
  PEERID_QUERY_INTERVAL=10800
  PEERID_QUERY_TIMER=0
  FIRST_QUERY_DONE=0
  
  # 新增：日志更新检测参数
  LOG_CHECK_INTERVAL=600        # 每10分钟检测一次日志
  LOG_CHECK_TIMER=0
  LOG_FILE="logs/swarm_launcher.log"  # 检测的日志文件
  LOG_TIMEOUT_MINUTES=20        # 20分钟无更新则重启
  LOG_TIMEOUT_SECONDS=$((LOG_TIMEOUT_MINUTES * 60))

  # 如果未找到 PY_PID，使用 RL_PID 进行监控
  if [ -z "$PY_PID" ]; then
    MONITOR_PID=$RL_PID
    log "🔍 RL-Swarm v${RL_SWARM_VERSION} 开始监控 RL_PID: $MONITOR_PID"
  else
    MONITOR_PID=$PY_PID
    log "🔍 RL-Swarm v${RL_SWARM_VERSION} 开始监控 PY_PID: $MONITOR_PID"
  fi

  while kill -0 "$MONITOR_PID" >/dev/null 2>&1; do
    sleep 2
    MEM_CHECK_TIMER=$((MEM_CHECK_TIMER + 2))
    PEERID_QUERY_TIMER=$((PEERID_QUERY_TIMER + 2))
    LOG_CHECK_TIMER=$((LOG_CHECK_TIMER + 2))
    if [ $MEM_CHECK_TIMER -ge $MEM_CHECK_INTERVAL ]; then
      MEM_CHECK_TIMER=0
      if [[ "$OSTYPE" == "darwin"* ]]; then
        FREE_GB=$(df -g / | awk 'NR==2 {print $4}')
      else
        FREE_GB=$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
      fi
      log "🔍 RL-Swarm v${RL_SWARM_VERSION} 检测到磁盘剩余空间 ${FREE_GB}GB"
      if [ "$FREE_GB" -lt "$DISK_LIMIT_GB" ]; then
        log "🚨 RL-Swarm v${RL_SWARM_VERSION} 磁盘空间不足（${FREE_GB}GB < ${DISK_LIMIT_GB}GB），自动重启！"
        cleanup restart
        break
      fi
    fi

    if [ $PEERID_QUERY_TIMER -ge $PEERID_QUERY_INTERVAL ]; then
      PEERID_QUERY_TIMER=0  # 重置计时器，避免持续输出日志
      
      if [ -f "$PEERID_LOG" ]; then
        PEER_ID=$(grep "Peer ID" "$PEERID_LOG" | sed -n 's/.*Peer ID \[\(.*\)\].*/\1/p' | tail -n1)
        if [ -n "$PEER_ID" ]; then
          echo "$PEER_ID" > "$PEERID_FILE"
          log "✅ RL-Swarm v${RL_SWARM_VERSION} 已检测并保存 Peer ID: $PEER_ID"
          query_and_save_peerid_info "$PEER_ID"
          FIRST_QUERY_DONE=1
        else
          log "⏳ RL-Swarm v${RL_SWARM_VERSION} 未检测到 Peer ID，等待下次查询..."
        fi
      else
        log "⏳ 未检测到 Peer ID 日志文件，等待下次查询..."
      fi
    fi
    
    # 新增：检测日志更新状态
    if [ $LOG_CHECK_TIMER -ge $LOG_CHECK_INTERVAL ]; then
      LOG_CHECK_TIMER=0  # 重置计时器
      
      if [ -f "$LOG_FILE" ]; then
        # 获取日志文件的最后修改时间
        if [[ "$OSTYPE" == "darwin"* ]]; then
          # macOS 使用 stat -f %m 获取最后修改时间戳
          LAST_MODIFY_TIME=$(stat -f %m "$LOG_FILE" 2>/dev/null)
        else
          # Linux 使用 stat -c %Y 获取最后修改时间戳
          LAST_MODIFY_TIME=$(stat -c %Y "$LOG_FILE" 2>/dev/null)
        fi
        
        if [[ -n "$LAST_MODIFY_TIME" ]]; then
          CURRENT_TIME=$(date +%s)
          TIME_DIFF=$((CURRENT_TIME - LAST_MODIFY_TIME))
          
          if [ $TIME_DIFF -gt $LOG_TIMEOUT_SECONDS ]; then
            log "🚨 RL-Swarm v${RL_SWARM_VERSION} 日志文件超过 ${LOG_TIMEOUT_MINUTES} 分钟未更新（${TIME_DIFF}秒），自动重启节点！"
            cleanup restart
            break
          else
            log "✅ RL-Swarm v${RL_SWARM_VERSION} 日志文件正常更新，最后更新时间：${TIME_DIFF}秒前"
          fi
        else
          log "⚠️ 无法获取日志文件修改时间，跳过本次检测"
        fi
      else
        log "⏳ 日志文件不存在，等待下次检测..."
      fi
    fi
  done

  # ✅ 清理并准备重启
  log "🚨 RL-Swarm v${RL_SWARM_VERSION} 监控进程 PID: $MONITOR_PID 已终止，进入重启流程"
  
  # 重启前检查代码更新
  check_and_update_code
  
  cleanup restart
  RETRY_COUNT=$((RETRY_COUNT + 1))

  if [ $RETRY_COUNT -eq $WARNING_THRESHOLD ]; then
    log "🚨 警告：RL Swarm v${RL_SWARM_VERSION} 已重启 $WARNING_THRESHOLD 次，请检查系统状态"
  fi

  sleep 2
done

log "🛑 RL-Swarm v${RL_SWARM_VERSION} 已达到最大重试次数 ($MAX_RETRIES)，程序退出"