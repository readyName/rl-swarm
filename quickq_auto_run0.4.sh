#!/bin/bash

APP_NAME="QuickQ"
APP_PATH="/Applications/QuickQ For Mac.app"

# 坐标参数说明：
# 连接操作坐标
DROP_DOWN_BUTTON_X=1720  # 下拉按钮X
DROP_DOWN_BUTTON_Y=430   # 下拉按钮Y
CONNECT_BUTTON_X=1720    # 连接按钮X
CONNECT_BUTTON_Y=260     # 连接按钮Y

# 初始化操作坐标
SETTINGS_BUTTON_X=1869   # 设置按钮X
SETTINGS_BUTTON_Y=165    # 设置按钮Y

# 检查 cliclick 依赖
if ! command -v cliclick &> /dev/null; then
    echo "正在通过Homebrew安装cliclick..."
    if ! command -v brew &> /dev/null; then
        echo "错误：请先安装Homebrew (https://brew.sh)"
        exit 1
    fi
    brew install cliclick
    
    # ===== 新增功能开始 =====
    echo "[$(date +"%T")] 依赖安装完成，正在执行一次性权限触发操作..."
    
    # 启动应用
    open "$APP_PATH"
    sleep 5  # 等待应用启动
    
    # 执行窗口调整和点击
    osascript -e 'tell application "QuickQ For Mac" to activate'
    sleep 1
    
    # 窗口校准函数调用
    adjust_window
    
    # 点击设置按钮（触发权限请求）
    cliclick c:${SETTINGS_BUTTON_X},${SETTINGS_BUTTON_Y}
    echo "[$(date +"%T")] 已触发点击事件，请检查系统权限请求"
    echo "[$(date +"%T")] 等待10秒以便您处理权限对话框..."
    sleep 10
    
    # 安全终止应用（因为主循环会重新启动它）
    pkill -9 -f "$APP_NAME"
    # ===== 新增功能结束 =====
fi

# 以下是原有脚本内容保持不变 ▼▼▼
reconnect_count=0
last_vpn_status="disconnected"

# VPN状态检测函数
check_vpn_connection() {
    local TEST_URLS=(
        "https://x.com"
        "https://www.google.com"
    )
    local TIMEOUT=3

    for url in "${TEST_URLS[@]}"; do
        if curl --silent --head --fail --max-time $TIMEOUT "$url" &> /dev/null; then
            echo "[$(date +"%T")] VPN检测：可通过 $url"
            last_vpn_status="connected"
            return 0
        fi
    done
    last_vpn_status="disconnected"
    return 1
}

# 窗口位置校准函数
adjust_window() {
    osascript <<'EOF'
    tell application "System Events"
        tell process "QuickQ For Mac"
            repeat 3 times  # 增加重试机制
                if exists window 1 then
                    set position of window 1 to {1520, 0}
                    set size of window 1 to {400, 300}
                    exit repeat
                else
                    delay 0.5
                end if
            end repeat
        end tell
    end tell
EOF
    echo "[$(date +"%T")] 窗口位置已校准"
    sleep 1  # 关键等待
}

# 执行标准连接流程
connect_procedure() {
    # 激活窗口
    osascript -e 'tell application "QuickQ For Mac" to activate'
    sleep 0.5
    
    adjust_window
    
    # 点击连接序列
    cliclick c:${DROP_DOWN_BUTTON_X},${DROP_DOWN_BUTTON_Y}
    echo "[$(date +"%T")] 已点击下拉菜单"
    sleep 1
    
    cliclick c:${CONNECT_BUTTON_X},${CONNECT_BUTTON_Y}
    echo "[$(date +"%T")] 已发起连接请求"
    sleep 15  # 连接等待时间
}

# 应用重启初始化流程
initialize_app() {
    echo "[$(date +"%T")] 执行初始化操作..."
    osascript -e 'tell application "QuickQ For Mac" to activate'
    adjust_window  # 新增窗口校准
    
    # 点击设置按钮
    cliclick c:${SETTINGS_BUTTON_X},${SETTINGS_BUTTON_Y}
    echo "[$(date +"%T")] 已点击设置按钮"
    sleep 2
    
    connect_procedure
}

# 安全终止应用
terminate_app() {
    echo "[$(date +"%T")] 正在停止应用..."
    pkill -9 -f "$APP_NAME" && echo "[$(date +"%T")] 已终止残留进程"
}

while :; do
    if pgrep -f "$APP_NAME" &> /dev/null; then
        if check_vpn_connection; then
            if [ "$last_vpn_status" == "disconnected" ]; then
                echo "[$(date +"%T")] 状态变化：已建立VPN连接"
            fi
            reconnect_count=0
            sleep 30
            continue
        else
            echo "[$(date +"%T")] 检测到网络不通"
            
            if [ $reconnect_count -lt 3 ]; then
                connect_procedure
                ((reconnect_count++))
                echo "[$(date +"%T")] 重试次数：$reconnect_count/3"
            else
                echo "[$(date +"%T")] 达到重试上限，执行应用重置"
                terminate_app
                
                # 重启流程
                open "$APP_PATH"
                echo "[$(date +"%T")] 应用启动中..."
                sleep 10  # 延长启动等待
                
                initialize_app  # 包含窗口校准和初始化点击
                
                reconnect_count=0
                sleep 10  # 重启后缓冲期
            fi
        fi
    else
        echo "[$(date +"%T")] 应用未运行，正在启动..."
        open "$APP_PATH"
        sleep 10
        initialize_app
    fi
    sleep 5
done
