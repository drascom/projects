#!/bin/bash

set -e

# === Settings ===
INSTALL_DIR="$HOME/ollama-interceptor"
SERVICE_NAME="mitmweb"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
else
    OS_TYPE="linux"
fi

echo "=== Detected OS: $OS_TYPE ==="
echo "=== Uninstalling Ollama Request Interceptor ==="

# Stop and remove service
if [ "$OS_TYPE" == "linux" ]; then
    echo "=== Stopping and removing systemd service ==="
    sudo systemctl stop $SERVICE_NAME 2>/dev/null || true
    sudo systemctl disable $SERVICE_NAME 2>/dev/null || true
    sudo rm -f /etc/systemd/system/$SERVICE_NAME.service
    sudo systemctl daemon-reload
elif [ "$OS_TYPE" == "macos" ]; then
    echo "=== Stopping and removing LaunchAgent ==="
    launchctl stop com.ollama.interceptor 2>/dev/null || true
    launchctl unload ~/Library/LaunchAgents/com.ollama.interceptor.plist 2>/dev/null || true
    rm -f ~/Library/LaunchAgents/com.ollama.interceptor.plist
fi

# Remove installation directory
echo "=== Removing installation directory ==="
rm -rf "$INSTALL_DIR"

echo "=== Uninstallation complete ==="
echo "✅ Ollama Request Interceptor has been removed from your system."
echo "Note: Any PATH modifications in your shell configuration files remain and can be manually removed if desired."