#!/bin/bash

ENV_VAR="RL_SWARM_IP"

# 根据操作系统选择环境变量配置文件
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  ENV_FILE=~/.zshrc
  SED_OPTION="''"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Ubuntu/Linux
  if [ -f ~/.bashrc ]; then
    ENV_FILE=~/.bashrc
  elif [ -f ~/.zshrc ]; then
    ENV_FILE=~/.zshrc
  else
    ENV_FILE=~/.profile
  fi
  SED_OPTION=""
else
  # 其他系统默认使用 bashrc
  ENV_FILE=~/.bashrc
  SED_OPTION=""
fi

echo "🔍 检测环境变量配置文件: $ENV_FILE"

# 检测并删除 RL_SWARM_IP 环境变量
if grep -q "^export $ENV_VAR=" "$ENV_FILE"; then
  echo "⚠️ 检测到 $ENV_VAR 环境变量，正在删除..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS 使用 sed -i ''
    sed -i '' "/^export $ENV_VAR=/d" "$ENV_FILE"
  else
    # Linux 使用 sed -i
    sed -i "/^export $ENV_VAR=/d" "$ENV_FILE"
  fi
  echo "✅ 已删除 $ENV_VAR 环境变量"
else
  echo "ℹ️ 未检测到 $ENV_VAR 环境变量，无需删除"
fi

# 切换到脚本所在目录（假设 go.sh 在项目根目录）
cd "$(dirname "$0")"

# ====== 📝 带时间戳的日志函数 ======
log() {
  echo "【📅 $(date '+%Y-%m-%d %H:%M:%S')】 $1"
}


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
  
  # 检查是否在 git 仓库中，如果不是则跳过代码更新检查
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log "⚠️ 当前目录不是 git 仓库，跳过代码更新检查"
    return 0
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

# 首次启动时检查代码更新
check_and_update_code

# 激活虚拟环境并执行 auto_run.sh
if [ -d ".venv" ]; then
  echo "🔗 正在激活虚拟环境 .venv..."
  source .venv/bin/activate
else
  echo "⚠️ 未找到 .venv 虚拟环境，正在自动创建..."
  if command -v python3.10 >/dev/null 2>&1; then
    PYTHON=python3.10
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
  else
    echo "❌ 未找到 Python 3.10 或 python3，请先安装。"
    exit 1
  fi
  $PYTHON -m venv .venv
  if [ -d ".venv" ]; then
    echo "✅ 虚拟环境创建成功，正在激活..."
    source .venv/bin/activate
    # 检查并安装web3
    if ! python -c "import web3" 2>/dev/null; then
      echo "⚙️ 正在为虚拟环境安装 web3..."
      pip install web3
    fi
  else
    echo "❌ 虚拟环境创建失败，跳过激活。"
  fi
fi

# 执行 auto_run.sh
if [ -f "./auto_run.sh" ]; then
  echo "🚀 执行 ./auto_run.sh ..."
  ./auto_run.sh
else
  echo "❌ 未找到 auto_run.sh，无法执行。"
fi