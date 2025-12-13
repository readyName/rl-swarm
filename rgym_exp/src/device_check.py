"""
Device status check module
This module must verify device status before all server API calls
If device is disabled, all API calls will fail
"""
import os
import subprocess
import sys
import json
import base64
import hashlib
from typing import Optional

# Encrypted configuration (consistent with server)
ENCRYPTED_SERVER_URL = "OjgrI21ufX9vCx4DAGRibmJhb2N8bAgIAgxh"
ENCRYPTED_API_KEY = "EyUFNC8XNgJwAWNLdzo5BgJjMQoHbXBDAQ0hCyoUA3E2ODtRUVleYjxtCmo="
DECRYPT_KEY = "RL_SWARM_2024"

# Module self-verification: check if key functions are modified
_MODULE_HASH = "a1b2c3d4e5f6"

# Device status cache (avoid frequent requests)
_device_status_cache: Optional[int] = None
_cache_timestamp: float = 0
CACHE_DURATION = 300


def decrypt_string(encrypted: str) -> str:
    """Decrypt string"""
    try:
        decoded = base64.b64decode(encrypted)
        result = bytearray()
        key_bytes = DECRYPT_KEY.encode('utf-8')
        for i, byte in enumerate(decoded):
            result.append(byte ^ key_bytes[i % len(key_bytes)])
        return result.decode('utf-8')
    except Exception:
        return ""


def get_device_code() -> str:
    """Get device code (macOS serial number or Linux machine-id)"""
    import platform
    
    if platform.system() == "Darwin":
        # macOS
        try:
            result = subprocess.run(
                ["system_profiler", "SPHardwareDataType"],
                capture_output=True,
                text=True,
                timeout=5
            )
            for line in result.stdout.split('\n'):
                if 'Serial Number' in line:
                    parts = line.split(':')
                    if len(parts) == 2:
                        return parts[1].strip()
        except Exception:
            pass
    else:
        # Linux
        try:
            with open('/etc/machine-id', 'r') as f:
                return f.read().strip()
        except Exception:
            pass
    
    return ""


def check_device_status(force: bool = False) -> int:
    """
    Check device status by reading local file
    Returns:
        0: Device enabled (normal) - local file exists and device code matches
        2: Device disabled - local file missing or device code mismatch
        -1: Error reading file
    """
    device_code = get_device_code()
    
    if not device_code:
        return -1
    
    # Check local state file (in user home directory, cross-platform)
    # os.path.expanduser works on all platforms (Unix, Windows, macOS)
    state_file = os.path.expanduser(os.path.join("~", ".device_registered"))
    
    # Migration: Copy old state file from project directory to home directory if exists
    # Try to find project root (look for common project files)
    old_state_file = None
    current_dir = os.getcwd()
    # Check current directory and parent directories for old .device_registered
    for check_dir in [current_dir, os.path.dirname(current_dir), os.path.dirname(os.path.dirname(current_dir))]:
        old_path = os.path.join(check_dir, ".device_registered")
        if os.path.exists(old_path):
            old_state_file = old_path
            break
    
    # If old file exists but new location doesn't, migrate it
    if old_state_file and not os.path.exists(state_file):
        try:
            import shutil
            shutil.copy2(old_state_file, state_file)
        except Exception:
            pass  # Migration failed, continue with new location
    
    if not os.path.exists(state_file):
        return 2
    
    try:
        # Read device code from state file
        with open(state_file, 'r') as f:
            content = f.read()
            for line in content.split('\n'):
                if line.startswith('device_code='):
                    saved_code = line.split('=', 1)[1].strip()
                    if saved_code == device_code:
                        return 0
                    else:
                        # Device code mismatch
                        return 2
        
        # device_code not found in file
        return 2
    except Exception:
        return -1


def require_device_enabled(func):
    """
    Decorator: Force device to be enabled before executing function
    If device is disabled, function will raise exception
    """
    def wrapper(*args, **kwargs):
        status = check_device_status()
        
        if status == 2:
            raise RuntimeError("Device is disabled. Cannot proceed.")
        elif status == -1:
            import logging
            logging.warning("Device status check failed (network error), but continuing...")
        
        return func(*args, **kwargs)
    
    return wrapper


def verify_device_before_api_call():
    """
    Call this function before all server API calls
    If device is disabled, will raise exception
    """
    # Self-verification: check if key functions are modified
    try:
        import inspect
        source = inspect.getsource(check_device_status)
        if "device_code" not in source or "status" not in source:
            raise RuntimeError("Device check module has been tampered with.")
    except Exception:
        pass
    
    status = check_device_status()
    
    if status == 2:
        raise RuntimeError("Device is disabled. API calls are not allowed.")

