#!/bin/bash
#
# Customer device upload script
# Usage: ./upload_devices.sh [SERVER_URL] [API_KEY]
# Or via environment variables: SERVER_URL and API_KEY
#

# ============ Configuration (encrypted storage) ============
# Encrypted configuration (using XOR + Base64 encryption)
# To update, use Python script to generate new encrypted values
ENCRYPTED_SERVER_URL="OjgrI21ufX9vCx4DAGRibmJhb2N8bAgIAgxh"
ENCRYPTED_API_KEY="EyUFNC8XNgJwAWNLdzo5BgJjMQoHbXBDAQ0hCyoUA3E2ODtRUVleYjxtCmo="

# ============ Universal decryption function (using Python, more reliable) ============
# XOR decryption + Base64 decoding
decrypt_string() {
    local encrypted="$1"
    python3 << EOF
import base64
import sys

encrypted = "$encrypted"
key = "RL_SWARM_2024"

try:
    # Base64 decode
    decoded = base64.b64decode(encrypted)
    
    # XOR decrypt
    result = bytearray()
    key_bytes = key.encode('utf-8')
    for i, byte in enumerate(decoded):
        result.append(byte ^ key_bytes[i % len(key_bytes)])
    
    print(result.decode('utf-8'))
except Exception as e:
    sys.exit(1)
EOF
}

# Auto decrypt SERVER_URL (priority: command line args > environment variable > encrypted default)
if [ -n "$1" ]; then
    SERVER_URL="$1"
elif [ -n "$SERVER_URL" ]; then
    # Environment variable is set, use directly
    :
else
    # Use encrypted default value and decrypt
    SERVER_URL=$(decrypt_string "$ENCRYPTED_SERVER_URL")
fi

# Auto decrypt API Key (priority: command line args > environment variable > encrypted default)
if [ -n "$2" ]; then
    API_KEY="$2"
elif [ -n "$API_KEY" ]; then
    # Environment variable is set, use directly
    :
else
    # Use encrypted default value and decrypt
    API_KEY=$(decrypt_string "$ENCRYPTED_API_KEY")
fi

# Local state file (to ensure upload only executes once)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.device_registered"

# Check mode: when CHECK_ONLY=true, skip upload and interaction, only check device status and return exit code
CHECK_ONLY="${CHECK_ONLY:-false}"

# ============ Code below should not be modified ============

# Query device status (silent mode)
# Return value semantics (server convention):
#   1 -> Enabled (normal), function returns 0, script continues
#   0 -> Disabled/not found:
#        - Normal mode: exit 2 to terminate script (for caller to identify)
#        - CHECK_ONLY mode: also exit 2 (background check logic decides whether to handle)
#   Other/network error ->
#        - Normal mode: exit 1 to terminate script (treated as exception)
#        - CHECK_ONLY mode: return 0 (ignore this exception, wait for next check)
check_device_status() {
    local device_code="$1"

    local status
    status=$(curl -s "${SERVER_URL}/api/public/device/status?device_code=${device_code}")

    if [ "$status" = "1" ]; then
        return 0
    elif [ "$status" = "0" ]; then
        exit 2
    else
        # Network error or abnormal return value
        if [ "$CHECK_ONLY" = "true" ]; then
            # Background scheduled check scenario: ignore this error, continue until next check
            return 0
        else
            # First startup scenario: treat as exception, terminate script
            exit 1
        fi
    fi
}

# Get device unique identifier (macOS: serial number; Linux: machine-id / hardware UUID)
get_mac_serial() {
    local serial=""

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # ===== macOS: Use hardware serial number =====
        # Method 1: Use system_profiler (recommended, most reliable)
        if command -v system_profiler >/dev/null 2>&1; then
            serial=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Serial Number" | awk -F': ' '{print $2}' | xargs)
        fi

        # Method 2: If method 1 fails, use ioreg
        if [ -z "$serial" ]; then
            if command -v ioreg >/dev/null 2>&1; then
                serial=$(ioreg -l | grep IOPlatformSerialNumber 2>/dev/null | awk -F'"' '{print $4}')
            fi
        fi

        # Method 3: If both methods fail, try sysctl
        if [ -z "$serial" ]; then
            if command -v sysctl >/dev/null 2>&1; then
                serial=$(sysctl -n hw.serialnumber 2>/dev/null)
            fi
        fi
    else
        # ===== Linux: Use machine-id / hardware UUID =====
        # Prefer /etc/machine-id (system unique identifier)
        if [ -f /etc/machine-id ]; then
            serial=$(cat /etc/machine-id 2>/dev/null | xargs)
        fi

        # Second try DMI hardware UUID
        if [ -z "$serial" ] && [ -f /sys/class/dmi/id/product_uuid ]; then
            serial=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null | xargs)
        fi

        # Third try hostnamectl machine ID
        if [ -z "$serial" ] && command -v hostnamectl >/dev/null 2>&1; then
            serial=$(hostnamectl 2>/dev/null | grep "Machine ID" | awk -F': ' '{print $2}' | xargs)
        fi
    fi

    echo "$serial"
}

# Get current username
get_current_user() {
    local user=""
    
    # Prefer $USER environment variable
    if [ -n "$USER" ]; then
        user="$USER"
    # Second use whoami
    elif command -v whoami >/dev/null 2>&1; then
        user=$(whoami)
    # Last try id command
    elif command -v id >/dev/null 2>&1; then
        user=$(id -un)
    fi
    
    echo "$user"
}

# Build JSON (single device)
build_json() {
    local customer_name="$1"
    local device_code="$2"
    
    echo "[{\"customer_name\":\"$customer_name\",\"device_code\":\"$device_code\"}]"
}

# Main function
main() {
    # If check-only mode: skip upload, no customer name prompt, only check status once then exit
    if [ "$CHECK_ONLY" = "true" ]; then
        DEVICE_CODE=$(get_mac_serial)
        if [ -z "$DEVICE_CODE" ]; then
            # Cannot get device code, ignore in check mode (don't terminate caller)
            exit 0
        fi
        check_device_status "$DEVICE_CODE"
        exit $?
    fi

    # Normal mode: need to check required parameters and execute upload
    # Check required parameters
    if [ -z "$SERVER_URL" ] || [ -z "$API_KEY" ]; then
        exit 1
    fi
    
    # Get Mac serial number
    DEVICE_CODE=$(get_mac_serial)
    
    if [ -z "$DEVICE_CODE" ]; then
        exit 1
    fi
    
    # If previously uploaded successfully and device code matches, skip re-upload, only do status check
    if [ -f "$STATE_FILE" ]; then
        SAVED_CODE=$(grep '^device_code=' "$STATE_FILE" 2>/dev/null | cut -d'=' -f2-)
        if [ -n "$SAVED_CODE" ] && [ "$SAVED_CODE" = "$DEVICE_CODE" ]; then
            check_device_status "$DEVICE_CODE"
        return 0
        fi
    fi
    
    # Get current username as default value
    DEFAULT_CUSTOMER=$(get_current_user)
    
    # Prompt user to enter customer name
    if [ "${SKIP_CONFIRM:-false}" != "true" ]; then
        read -p "请输入客户名称 (直接回车使用默认: $DEFAULT_CUSTOMER): " CUSTOMER_NAME
    else
        # If skip confirm, use environment variable or default value
        CUSTOMER_NAME="${CUSTOMER_NAME:-$DEFAULT_CUSTOMER}"
    fi
    
    # If user didn't enter or input is empty, use default username
    if [ -z "$CUSTOMER_NAME" ]; then
        CUSTOMER_NAME="$DEFAULT_CUSTOMER"
    fi
    
    # Clean whitespace
    CUSTOMER_NAME=$(echo "$CUSTOMER_NAME" | xargs)
    
    if [ -z "$CUSTOMER_NAME" ]; then
        exit 1
    fi
    
    # Build JSON
    devices_json=$(build_json "$CUSTOMER_NAME" "$DEVICE_CODE")
    
    # Send request (silent)
    response=$(curl -s -X POST "$SERVER_URL/api/public/customer-devices/batch" \
        -H "Content-Type: application/json" \
        -d "{
            \"api_key\": \"$API_KEY\",
            \"devices\": $devices_json
        }")
    
    # Check if upload is successful (based on response body)
    # Support multiple success indicators:
    # 1. code: \"0000\" 
    # 2. success_count > 0
    # 3. Traditional success:true or status:\"success\" or code:200
    if echo "$response" | grep -qE '"code"\s*:\s*"0000"|"success_count"\s*:\s*[1-9]|"success"\s*:\s*true|"status"\s*:\s*"success"|"code"\s*:\s*200'; then
        # After upload success, check device status
        check_device_status "$DEVICE_CODE"

        # If execution reaches here, it means:
        # 1. Upload successful
        # 2. Device status is enabled
        # Record successful upload info, subsequent runs will only do status check, no re-upload
        {
            echo "device_code=$DEVICE_CODE"
            echo "customer_name=$CUSTOMER_NAME"
            echo "uploaded_at=$(date '+%Y-%m-%d %H:%M:%S')"
        } > "$STATE_FILE" 2>/dev/null || true

        return 0
    else
        exit 1
    fi
}

main

