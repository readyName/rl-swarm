#!/bin/bash

APP_NAME="QuickQ"
APP_PATH="/Applications/QuickQ For Mac.app"
ICON_X=1720
ICON_Y=260
ICON_Z=430  # 修正变量名大小写（原为ICON_z）

# 检查 cliclick 是否已安装
if ! command -v cliclick &> /dev/null; then
    echo "cliclick 未安装，正在尝试用 Homebrew 安装..."
    if command -v brew &> /dev/null; then
        brew install cliclick
    else
        echo "未检测到 Homebrew，请先手动安装 Homebrew 后再运行本脚本。"
        exit 1
    fi
fi

reconnect_count=0

while true
do
    # 检查QuickQ进程是否存在
    if pgrep -f "$APP_NAME" > /dev/null; then
        # 检查外网IP是否为VPN出口IP
        if curl -I --max-time 5 https://www.google.com 2>/dev/null | grep -q "HTTP/2 200"; then
            echo "$(date): $APP_NAME 正常运行且VPN已连接"
            reconnect_count=0  # 连接成功，重置计数
        else
            echo "$(date): $APP_NAME 正常运行但VPN未连接，尝试重连"
# 3. 使用固定坐标移动窗口（基于 1920x1080 分辨率）
        osascript <<'EOF'  # 使用单引号防止变量扩展
        tell application "System Events"
            # 检查 QuickQ 是否运行
            set isRunning to exists (processes where name is "QuickQ For Mac")
            if not isRunning then
                display dialog "QuickQ 未启动成功，请检查应用路径或权限。" buttons {"OK"} default button 1
                return
            end if
            # 激活并移动窗口到右上角
            tell application "QuickQ For Mac" to activate
            delay 1
    
            tell process "QuickQ For Mac"
                # 固定坐标：右上角 (1920 - 窗口宽度, 0)
                set position of window 1 to {1520, 0}  # 假设窗口宽度为 400
                set size of window 1 to {400, 300}    # 窗口大小 (宽 x 高)
            end tell
        end tell
EOF
            cliclick c:${ICON_X},${ICON_Z}  # 使用修正后的变量名
            sleep 1 
            cliclick c:${ICON_X},${ICON_Y}
            echo "$(date): 已自动点击连接图标，请勿移动鼠标"
            sleep 20  # 等待程序启动20秒

            reconnect_count=$((reconnect_count+1))
            echo "当前重连次数: $reconnect_count"
            if [ "$reconnect_count" -ge 10 ]; then
                echo "重连已达10次，准备重启 $APP_NAME 并重置计数"
                pids=$(pgrep -f "$APP_NAME")
                if [ -n "$pids" ]; then
                    echo "发现残留进程: $pids，正在杀死..."
                    kill -9 $pids
                    echo "残留进程已杀死"
                fi
                open "$APP_PATH"
                sleep 3
                osascript <<'EOF'  # 使用单引号防止变量扩展
                tell application "System Events"
                    # 检查 QuickQ 是否运行
                    set isRunning to exists (processes where name is "QuickQ For Mac")
                    if not isRunning then
                        display dialog "QuickQ 未启动成功，请检查应用路径或权限。" buttons {"OK"} default button 1
                        return
                    end if
                    # 激活并移动窗口到右上角
                    tell application "QuickQ For Mac" to activate
                    delay 1
    
                    tell process "QuickQ For Mac"
                        # 固定坐标：右上角 (1920 - 窗口宽度, 0)
                        set position of window 1 to {1520, 0}  # 假设窗口宽度为 400
                        set size of window 1 to {400, 300}    # 窗口大小 (宽 x 高)
                    end tell
                end tell
EOF
                echo "$(date): $APP_NAME 已打开，准备自动连接vpn"
                sleep 5
                cliclick c:${ICON_X},${ICON_Z}  # 使用修正后的变量名
                sleep 1
                cliclick c:${ICON_X},${ICON_Y}
                echo "$(date): 已自动点击连接图标"
                sleep 20
                reconnect_count=0
            fi
        fi
    else
        echo "$(date): $APP_NAME 已宕机，尝试清理残留进程"
        # 查找并杀死所有相关进程
        pids=$(pgrep -f "$APP_NAME")
        if [ -n "$pids" ]; then
            echo "发现残留进程: $pids，正在杀死..."
            kill -9 $pids
            echo "残留进程已杀死"
        else
            echo "未发现残留进程"
        fi

        echo "准备重启 $APP_NAME"
        sleep 1
        open "$APP_PATH"
        sleep 3
        # 3. 使用固定坐标移动窗口（基于 1920x1080 分辨率）
        osascript <<'EOF'  # 使用单引号防止变量扩展
        tell application "System Events"
            # 检查 QuickQ 是否运行
            set isRunning to exists (processes where name is "QuickQ For Mac")
            if not isRunning then
                display dialog "QuickQ 未启动成功，请检查应用路径或权限。" buttons {"OK"} default button 1
                return
            end if
            # 激活并移动窗口到右上角
            tell application "QuickQ For Mac" to activate
            delay 1
    
            tell process "QuickQ For Mac"
                # 固定坐标：右上角 (1920 - 窗口宽度, 0)
                set position of window 1 to {1520, 0}  # 假设窗口宽度为 400
                set size of window 1 to {400, 300}    # 窗口大小 (宽 x 高)
            end tell
        end tell
EOF
        echo "$(date): $APP_NAME 已打开，准备自动连接vpn"
        sleep 5 # 等待程序启动5秒
        cliclick c:${ICON_X},${ICON_Z}  # 使用修正后的变量名
        sleep 1
        cliclick c:${ICON_X},${ICON_Y}
        echo "$(date): 已自动点击连接图标"
        sleep 20  # 等待程序启动20秒
        reconnect_count=0  # 应用重启，重置计数
    fi
    sleep 5
done