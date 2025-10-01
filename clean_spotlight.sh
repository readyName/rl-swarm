#!/bin/bash

# Spotlight 索引清理脚本
# 用于清理 macOS Spotlight 索引并重建

echo "=========================================="
echo "🔍 Spotlight 索引清理脚本"
echo "=========================================="
echo "⚠️  此脚本需要管理员权限来操作系统文件"
echo "📝 将要求输入开机密码"
echo "=========================================="
echo ""

# 检查是否已有sudo权限
if ! sudo -n true 2>/dev/null; then
    echo "🔐 需要管理员权限，请输入开机密码："
    echo ""
fi

echo "开始清理 Spotlight 索引..."

# 0)（可选但推荐）确认目录和体积
echo "检查 Spotlight 目录大小和内容..."
sudo du -sh /System/Volumes/Data/.Spotlight-V100 2>/dev/null || true
sudo ls -la /System/Volumes/Data/.Spotlight-V100 2>/dev/null || true

# 1) 关闭所有卷的 Spotlight 索引
echo "关闭所有卷的 Spotlight 索引..."
sudo mdutil -a -i off
echo "当前索引状态："
mdutil -as

# 2) 解除不可变标志（保险起见）
echo "解除不可变标志..."
sudo chflags -R nouchg /System/Volumes/Data/.Spotlight-V100 2>/dev/null || true

# 3) **不要用 * 通配符**，直接把目录整个删掉
echo "删除 Spotlight 索引目录..."
sudo rm -rf /System/Volumes/Data/.Spotlight-V100

# 4) 重新开启并强制重建索引
echo "重新开启 Spotlight 索引..."
sudo mdutil -i on /
echo "强制重建索引..."
sudo mdutil -E /
echo "最终索引状态："
mdutil -s /

echo "Spotlight 索引清理完成！"