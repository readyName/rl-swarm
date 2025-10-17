#!/bin/bash

CONFIG_FILE="rgym_exp/config/rg-swarm.yaml"

ZSHRC=~/.zshrc
ENV_VAR="RL_SWARM_IP"

# ----------- IP配置逻辑 -----------
echo "🔧 检查IP配置..."

# 确保 zshrc 文件存在，避免 grep 报错
[ -f "$ZSHRC" ] || touch "$ZSHRC"

# 读取 ~/.zshrc 的 RL_SWARM_IP 环境变量
if grep -q "^export $ENV_VAR=" "$ZSHRC"; then
  CURRENT_IP=$(grep "^export $ENV_VAR=" "$ZSHRC" | tail -n1 | awk -F'=' '{print $2}' | tr -d '[:space:]')
else
  CURRENT_IP=""
fi

# 交互提示（10秒超时）
if [ -n "$CURRENT_IP" ]; then
  echo -n "检测到上次使用的 IP: $CURRENT_IP，是否继续使用？(Y/n, 10秒后默认Y): "
  read -t 10 USE_LAST
  if [[ "$USE_LAST" == "" || "$USE_LAST" =~ ^[Yy]$ ]]; then
    NEW_IP="$CURRENT_IP"
  else
    read -p "请输入新的 initial_peers IP（直接回车跳过IP配置）: " NEW_IP
  fi
else
  read -p "未检测到历史 IP，请输入 initial_peers IP（直接回车跳过IP配置）: " NEW_IP
fi

# 每次都将环境变量中的IP写入 ~/.zshrc，保证同步
if [ -n "$CURRENT_IP" ]; then
  sed -i '' "/^export $ENV_VAR=/d" "$ZSHRC"
  echo "export $ENV_VAR=$CURRENT_IP" >> "$ZSHRC"
  echo "✅ 已同步环境变量IP到配置文件：$CURRENT_IP"
fi

# 继续后续逻辑
if [[ -z "$NEW_IP" ]]; then
  echo "ℹ️ 未输入IP，跳过所有IP相关配置，继续执行。"
else
  # 只要有NEW_IP都写入一次配置文件
  sed -i '' "/^export $ENV_VAR=/d" "$ZSHRC"
  echo "export $ENV_VAR=$NEW_IP" >> "$ZSHRC"
  echo "✅ 已写入IP到配置文件：$NEW_IP"
  # 备份原文件
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

  # 替换 initial_peers 下的 IP
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS: 匹配 /ip4/旧IP/tcp/端口/p2p/节点ID 格式，只替换IP部分
    sed -i '' "s|/ip4/[0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}|/ip4/${NEW_IP}|g" "$CONFIG_FILE"
  else
    # Linux: 匹配 /ip4/旧IP/tcp/端口/p2p/节点ID 格式，只替换IP部分
    sed -i "s|/ip4/[0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}|/ip4/${NEW_IP}|g" "$CONFIG_FILE"
  fi

  echo "✅ 已将 initial_peers 的 IP 全部替换为：$NEW_IP"
  echo "原始文件已备份为：${CONFIG_FILE}.bak"
fi

# 切换到脚本所在目录（假设 go.sh 在项目根目录）
cd "$(dirname "$0")"

# ====== 📝 带时间戳的日志函数 ======
log() {
  echo "【📅 $(date '+%Y-%m-%d %H:%M:%S')】 $1"
}

# ====== 重新创建虚拟环境函数 ======
recreate_virtual_environment() {
  log "🔄 代码已更新，正在重新创建虚拟环境..."
  
  # 删除现有的虚拟环境
  if [ -d ".venv" ]; then
    log "🗑️ 删除现有虚拟环境 .venv..."
    rm -rf .venv
    log "✅ 虚拟环境已删除"
  fi
  
  # 确定 Python 版本
  if command -v python3.10 >/dev/null 2>&1; then
    PYTHON=python3.10
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
  else
    log "❌ 未找到 Python 3.10 或 python3，无法创建虚拟环境"
    return 1
  fi
  
  # 创建新的虚拟环境
  log "🆕 正在创建新的虚拟环境 .venv..."
  if $PYTHON -m venv .venv; then
    log "✅ 虚拟环境创建成功"
    
    # 激活虚拟环境
    log "🔗 正在激活新的虚拟环境..."
    source .venv/bin/activate
    
    # 安装必要的依赖
    log "⚙️ 正在安装 web3 依赖..."
    if pip install web3 2>/dev/null; then
      log "✅ web3 依赖安装成功"
    else
      log "⚠️ web3 依赖安装失败，但继续执行"
    fi
    
    log "✅ 虚拟环境重新创建完成"
    return 0
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
    
    # 代码更新成功后，删除并重新创建虚拟环境
    recreate_virtual_environment
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
        
        # 强制更新成功后，删除并重新创建虚拟环境
        recreate_virtual_environment
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

# 每次启动都重新创建虚拟环境
log "🔄 每次启动都重新创建虚拟环境..."
recreate_virtual_environment

# 激活虚拟环境并执行 auto_run.sh
# 由于每次启动都重新创建了虚拟环境，直接激活即可
if [ -d ".venv" ]; then
  log "🔗 正在激活虚拟环境 .venv..."
  source .venv/bin/activate
else
  log "❌ 虚拟环境不存在，无法激活"
  exit 1
fi

# 执行 auto_run.sh
if [ -f "./auto_run.sh" ]; then
  echo "🚀 执行 ./auto_run.sh ..."
  ./auto_run.sh
else
  echo "❌ 未找到 auto_run.sh，无法执行。"
fi