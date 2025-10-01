#!/bin/bash

# 1. 获取当前终端的窗口ID并关闭其他终端窗口（排除当前终端）
current_window_id=$(osascript -e 'tell app "Terminal" to id of front window')
echo "当前终端窗口ID: $current_window_id，正在保护此终端不被关闭..."

osascript <<EOF
tell application "Terminal"
    activate
    set windowList to every window
    repeat with theWindow in windowList
        if id of theWindow is not ${current_window_id} then
            try
                close theWindow saving no
            end try
        end if
    end repeat
end tell
EOF
sleep 2


# 获取屏幕尺寸（使用系统信息替代Finder）
echo "正在获取屏幕尺寸..."
if command -v system_profiler >/dev/null 2>&1; then
    # macOS 使用 system_profiler 获取屏幕信息
    screen_info=$(system_profiler SPDisplaysDataType | grep Resolution | head -1 | awk '{print $2, $4}' | tr 'x' ' ')
    if [[ -n "$screen_info" ]]; then
        read -r width height <<< "$screen_info"
        x1=0
        y1=0
        x2=$width
        y2=$height
        echo "检测到屏幕尺寸: ${width}x${height}"
    else
        # 默认值
        width=1920
        height=1080
        x1=0
        y1=0
        x2=1920
        y2=1080
        echo "使用默认屏幕尺寸: ${width}x${height}"
    fi
else
    # 备用方案：使用默认值
    width=1920
    height=1080
    x1=0
    y1=0
    x2=1920
    y2=1080
    echo "使用默认屏幕尺寸: ${width}x${height}"
fi

# 窗口排列函数
function arrange_window {
    local title=$1
    local x=$2
    local y=$3
    local w=$4
    local h=$5
    
    # 计算窗口边界
    local right_x=$((x + w))
    local bottom_y=$((y + h))
    
    echo "排列窗口 '$title': 位置($x, $y), 大小(${w}x${h}), 边界(${right_x}x${bottom_y})"
    
    # 使用 osascript -e 避免 here document 变量替换问题
    if osascript -e "tell application \"Terminal\" to set bounds of first window whose name contains \"$title\" to {$x, $y, $right_x, $bottom_y}" 2>/dev/null; then
        echo "✅ 窗口 '$title' 排列成功"
    else
        echo "⚠️ 窗口 '$title' 排列失败，尝试备用方法..."
        # 备用方法：使用窗口ID
        local window_id=$(osascript -e "tell application \"Terminal\" to id of first window whose name contains \"$title\"" 2>/dev/null)
        if [[ -n "$window_id" ]]; then
            osascript -e "tell application \"Terminal\" to set bounds of window id $window_id to {$x, $y, $right_x, $bottom_y}" 2>/dev/null
            echo "✅ 窗口 '$title' (ID: $window_id) 排列成功"
        else
            echo "❌ 无法找到窗口 '$title'"
        fi
    fi
}

# 布局参数
spacing=20  # 间距20px
upper_height=$((height/2-2*spacing))  # 上层高度总共减少40px
lower_height=$((height/2-2*spacing))  # 下层高度总共减少40px
lower_y=$((y1+upper_height+2*spacing))  # 下层基准位置下移40px

# 上层布局（gensyn和wai）
upper_item_width=$(( (width-spacing)/2 ))  # 上层两个窗口的参考宽度，中间留20px间距

# 下层布局（nexus、Ritual）
# nexus和Ritual平分下层宽度
lower_item_width=$(( (width-spacing)/2 ))  # nexus和Ritual平分宽度，中间留20px间距
nexus_ritual_height=$((lower_height-30))  # nexus和Ritual高度减小30px
nexus_ritual_y=$((lower_y+5))  # nexus和Ritual向下移动5px

# wai宽度缩小1/2，高度保持不变（1倍）
wai_width=$((upper_item_width/2))  # wai宽度缩小为原来1/2
wai_height=$upper_height  # wai高度保持不变

# 3. 启动Docker（不新建终端窗口）
echo "✅ 正在后台启动Docker..."
open -a Docker --background

# 等待Docker完全启动
echo "⏳ 等待Docker服务就绪..."
until docker info >/dev/null 2>&1; do sleep 1; done
sleep 30  # 额外等待确保完全启动

# 4. 启动gensyn（上层左侧，距离左边界30px）
osascript -e 'tell app "Terminal" to do script "until docker info >/dev/null 2>&1; do sleep 1; done && cd ~/rl-swarm && ./gensyn.sh"'
sleep 1
arrange_window "gensyn" $((x1+30)) $y1 $upper_item_width $upper_height

# 5. 启动dria（上层右侧，向右偏移半个身位，宽度缩小1/2，高度不变）
osascript -e 'tell app "Terminal" to do script "cd ~/rl-swarm && dkn-compute-launcher start"'
sleep 1
arrange_window "dkn-compute-launcher" $((x1+upper_item_width+spacing+upper_item_width/2)) $y1 $wai_width $wai_height

# 6. 启动nexus（下层左侧，高度减小30px，向下移动5px）
osascript -e 'tell app "Terminal" to do script "cd ~/rl-swarm && ./nexus.sh"'
sleep 1
arrange_window "nexus" $x1 $nexus_ritual_y $lower_item_width $nexus_ritual_height

# 7. 启动Ritual（下层右侧，高度减小30px，向下移动5px）
osascript -e 'tell app "Terminal" to do script "cd ~/rl-swarm && ./ritual.sh"'
sleep 1
arrange_window "Ritual" $((x1+lower_item_width+spacing)) $nexus_ritual_y $lower_item_width $nexus_ritual_height

echo "✅ 所有项目已启动完成！"
echo "   - Docker已在后台运行"
