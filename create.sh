#!/bin/bash

set -e
set -o pipefail

# 仅在 macOS 下生成 .command 文件
if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "ℹ️ 当前系统非 macOS，跳过生成 .command 文件"
  exit 0
fi

CURRENT_USER=$(whoami)
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DESKTOP_DIR="/Users/$CURRENT_USER/Desktop"
mkdir -p "$DESKTOP_DIR"

# 需要生成的脚本列表（不包含 wai.sh）
SCRIPTS=(
  gensyn.sh
  nexus.sh
  ritual.sh
  startAll.sh
)

for script in "${SCRIPTS[@]}"; do
  cmd_name="${script%.sh}.command"
  cat > "$DESKTOP_DIR/$cmd_name" <<EOF
#!/bin/bash

set -e

trap 'echo -e "\n\033[33m⚠️ 脚本被中断，但终端将继续运行...\033[0m"; exit 0' INT TERM

cd "$PROJECT_DIR" || { echo "❌ 无法进入项目目录"; exit 1; }

echo "🚀 正在执行 $script..."
./$script

echo -e "\n\033[32m✅ $script 执行完成\033[0m"
echo "按任意键关闭此窗口..."
read -n 1 -s
EOF
  chmod +x "$DESKTOP_DIR/$cmd_name"
  echo "✅ 已生成 $cmd_name"

done

echo "✅ 所有 .command 文件已生成到桌面（不包含 wai.command）"
