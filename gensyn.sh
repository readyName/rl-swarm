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
    echo "❌ 未找到 Python 3.12 或 python3，请先安装。"
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