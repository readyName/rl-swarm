#!/bin/bash

APP_NAME="QuickQ"
APP_PATH="/Applications/QuickQ For Mac.app"
ICON_X=1720
ICON_Y=260
ICON_Z=430  # ICON_z

#  cliclick 
if ! command -v cliclick &> /dev/null; then
    echo "cliclick  Homebrew ..."
    if command -v brew &> /dev/null; then
        brew install cliclick
    else
        echo " Homebrew Homebrew "
        exit 1
    fi
fi

reconnect_count=0

while true
do
    if pgrep -f "$APP_NAME" > /dev/null; then
        if ping -c 2 -W 2 google.com > /dev/null 2>&1; then
            echo "$(date): $APP_NAME VPN"
            reconnect_count=0
        else
            echo "$(date): $APP_NAME VPN"

            osascript <<'EOF'
            tell application "System Events"
                set isRunning to exists (processes where name is "QuickQ For Mac")
                if not isRunning then
                    display dialog "QuickQ " buttons {"OK"} default button 1
                    return
                end if
                tell application "QuickQ For Mac" to activate
                delay 1
                tell process "QuickQ For Mac"
                    set position of window 1 to {1520, 0}
                    set size of window 1 to {400, 300}
                end tell
            end tell
EOF

            cliclick c:${ICON_X},${ICON_Z}
            sleep 1
            cliclick c:${ICON_X},${ICON_Y}
            echo "$(date): "
            sleep 20

            reconnect_count=$((reconnect_count+1))
            echo ": $reconnect_count"

            if [ "$reconnect_count" -ge 10 ]; then
                echo "10 $APP_NAME "
                pids=$(pgrep -f "$APP_NAME")
                if [ -n "$pids" ]; then
                    echo ": $pids..."
                    kill -9 $pids
                    echo ""
                fi
                open "$APP_PATH"
                sleep 3
                osascript <<'EOF'
                tell application "System Events"
                    set isRunning to exists (processes where name is "QuickQ For Mac")
                    if not isRunning then
                        display dialog "QuickQ " buttons {"OK"} default button 1
                        return
                    end if
                    tell application "QuickQ For Mac" to activate
                    delay 1
                    tell process "QuickQ For Mac"
                        set position of window 1 to {1520, 0}
                        set size of window 1 to {400, 300}
                    end tell
                end tell
EOF
                echo "$(date): $APP_NAME VPN"
                sleep 5
                cliclick c:${ICON_X},${ICON_Z}
                sleep 1
                cliclick c:${ICON_X},${ICON_Y}
                echo "$(date): "
                sleep 20
                reconnect_count=0
            fi
        fi
    else
        echo "$(date): $APP_NAME "
        pids=$(pgrep -f "$APP_NAME")
        if [ -n "$pids" ]; then
            echo ": $pids..."
            kill -9 $pids
            echo ""
        fi

        echo " $APP_NAME"
        sleep 1
        open "$APP_PATH"
        sleep 3
        osascript <<'EOF'
        tell application "System Events"
            set isRunning to exists (processes where name is "QuickQ For Mac")
            if not isRunning then
                display dialog "QuickQ " buttons {"OK"} default button 1
                return
            end if
            tell application "QuickQ For Mac" to activate
            delay 1
            tell process "QuickQ For Mac"
                set position of window 1 to {1520, 0}
                set size of window 1 to {400, 300}
            end tell
        end tell
EOF
        echo "$(date): $APP_NAME VPN"
        sleep 5
        cliclick c:${ICON_X},${ICON_Z}
        sleep 1
        cliclick c:${ICON_X},${ICON_Y}
        echo "$(date): "
        sleep 20
        reconnect_count=0
    fi

    #  
    sleep 60
done
