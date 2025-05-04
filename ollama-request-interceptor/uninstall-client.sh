#!/bin/bash

set -e

# === Settings ===
INSTALL_DIR="$HOME/ollama-interceptor-client"

echo "=== Uninstalling Ollama Request Interceptor Client ==="

# Remove installation directory
echo "=== Removing installation directory ==="
rm -rf "$INSTALL_DIR"

echo "=== Uninstallation complete ==="
echo "✅ Ollama Request Interceptor Client has been removed from your system."
