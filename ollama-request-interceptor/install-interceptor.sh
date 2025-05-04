#!/bin/bash

set -e

# === Settings ===
INSTALL_DIR="$HOME/ollama-interceptor"
VENV_DIR="$INSTALL_DIR/mitmproxy-env"
SERVICE_NAME="mitmweb"

# Default settings (will be overridden by .env if it exists)
TARGET_URL="http://localhost:11434"
INTERCEPT_PORT=8080
WEB_UI_PORT=8081

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating default .env file..."
    cp .env.example .env
fi

# Load environment variables from .env
if [ -f .env ]; then
    echo "Loading configuration from .env file..."
    # Use grep and cut to extract values (more portable than source)
    ENV_TARGET_URL=$(grep -E '^TARGET_URL=' .env | cut -d '=' -f 2-)
    ENV_INTERCEPT_PORT=$(grep -E '^INTERCEPT_PORT=' .env | cut -d '=' -f 2-)
    ENV_WEB_UI_PORT=$(grep -E '^WEB_UI_PORT=' .env | cut -d '=' -f 2-)

    # Override defaults if values are set in .env
    [ -n "$ENV_TARGET_URL" ] && TARGET_URL="$ENV_TARGET_URL"
    [ -n "$ENV_INTERCEPT_PORT" ] && INTERCEPT_PORT="$ENV_INTERCEPT_PORT"
    [ -n "$ENV_WEB_UI_PORT" ] && WEB_UI_PORT="$ENV_WEB_UI_PORT"
fi

echo "=== Configuration ==="
echo "Target URL: $TARGET_URL"
echo "Intercept Port: $INTERCEPT_PORT"
echo "Web UI Port: $WEB_UI_PORT"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
else
    OS_TYPE="linux"
fi

echo "=== Detected OS: $OS_TYPE ==="

if [ "$OS_TYPE" == "linux" ]; then
    echo "=== Installing system packages (Linux) ==="
    sudo apt update
    sudo apt install -y python3 python3-pip python3-venv curl lsof
elif [ "$OS_TYPE" == "macos" ]; then
    echo "=== Installing system packages (macOS) ==="
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        echo "Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Install required packages
    brew install python3 curl
fi

echo "=== Installing uv (fast environment manager) ==="
curl -Ls https://astral.sh/uv/install.sh | sh
export PATH=$PATH:$HOME/.local/bin

if [ "$OS_TYPE" == "linux" ]; then
    echo 'export PATH=$PATH:$HOME/.local/bin' >> $HOME/.bashrc
    # Source only if the file exists and is readable
    [ -r "$HOME/.bashrc" ] && source "$HOME/.bashrc"
elif [ "$OS_TYPE" == "macos" ]; then
    # Add to bash profile if it exists
    [ -f "$HOME/.bash_profile" ] && echo 'export PATH=$PATH:$HOME/.local/bin' >> "$HOME/.bash_profile"

    # For zsh, append to zshrc but don't source it to avoid errors
    if [ -f "$HOME/.zshrc" ]; then
        # Check if PATH is already in .zshrc to avoid duplicates
        if ! grep -q "export PATH=\$PATH:\$HOME/.local/bin" "$HOME/.zshrc"; then
            echo 'export PATH=$PATH:$HOME/.local/bin' >> "$HOME/.zshrc"
        fi
    fi

    # Just export the PATH for the current session instead of sourcing
    export PATH=$PATH:$HOME/.local/bin
fi

echo "=== Creating install directory at $INSTALL_DIR ==="
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Copy .env file to installation directory
if [ -f "$OLDPWD/.env" ]; then
    echo "=== Copying .env file to installation directory ==="
    cp "$OLDPWD/.env" "$INSTALL_DIR/.env"
fi

echo "=== Creating UV environment and installing mitmproxy ==="
uv venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
uv pip install mitmproxy

echo "=== Creating ollama_intercept.py ==="
cat << 'EOF' > "$INSTALL_DIR/ollama_intercept.py"
from mitmproxy import http

def request(flow: http.HTTPFlow) -> None:
    if "api/chat" in flow.request.pretty_url:
        print("=== Intercepted Request ===")
        print(flow.request.method, flow.request.pretty_url)
        print(flow.request.headers)
        print(flow.request.content)

def response(flow: http.HTTPFlow) -> None:
    if "api/chat" in flow.request.pretty_url:
        print("=== Intercepted Response ===")
        print(flow.response.status_code)
        print(flow.response.headers)
        print(flow.response.content)
EOF

echo "=== Creating start-mitmweb.sh ==="
cat << EOF > "$INSTALL_DIR/start-mitmweb.sh"
#!/bin/bash

INSTALL_DIR="$INSTALL_DIR"
VENV_DIR="$VENV_DIR"
OLLAMA_TARGET="$TARGET_URL"
FIXED_PORT=$INTERCEPT_PORT
WEB_UI_PORT=$WEB_UI_PORT

# Load environment variables from .env if it exists
if [ -f "\$INSTALL_DIR/.env" ]; then
    echo "Loading configuration from .env file..."
    # Use grep and cut to extract values
    ENV_TARGET_URL=\$(grep -E '^TARGET_URL=' "\$INSTALL_DIR/.env" | cut -d '=' -f 2-)
    ENV_INTERCEPT_PORT=\$(grep -E '^INTERCEPT_PORT=' "\$INSTALL_DIR/.env" | cut -d '=' -f 2-)
    ENV_WEB_UI_PORT=\$(grep -E '^WEB_UI_PORT=' "\$INSTALL_DIR/.env" | cut -d '=' -f 2-)

    # Override defaults if values are set in .env
    [ -n "\$ENV_TARGET_URL" ] && OLLAMA_TARGET="\$ENV_TARGET_URL"
    [ -n "\$ENV_INTERCEPT_PORT" ] && FIXED_PORT="\$ENV_INTERCEPT_PORT"
    [ -n "\$ENV_WEB_UI_PORT" ] && WEB_UI_PORT="\$ENV_WEB_UI_PORT"
fi

# Activate UV environment
if [ -d "\$VENV_DIR" ]; then
    echo "Activating UV environment..."
    source "\$VENV_DIR/bin/activate"
else
    echo "UV environment not found at \$VENV_DIR!"
    exit 1
fi

# Check if port is free
if command -v lsof &> /dev/null && lsof -i ":\$FIXED_PORT" >/dev/null; then
    echo "❌ ERROR: Port \$FIXED_PORT is already in use. Cannot start mitmweb."
    exit 1
fi

# Start mitmweb
echo "✅ Port \$FIXED_PORT is free. Starting mitmweb..."
echo "Web UI available at http://localhost:\$WEB_UI_PORT/"

mitmweb --mode reverse:\${OLLAMA_TARGET}@\${FIXED_PORT} -p \${FIXED_PORT} --web-port \${WEB_UI_PORT} --web-host 0.0.0.0 --allow-hosts ".*" -s "\$INSTALL_DIR/ollama_intercept.py"
EOF

chmod +x "$INSTALL_DIR/start-mitmweb.sh"

if [ "$OS_TYPE" == "linux" ]; then
    echo "=== Creating $SERVICE_NAME.service ==="
    sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null << EOF
[Unit]
Description=Mitmweb Interceptor Service
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/start-mitmweb.sh
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=5
User=$USER
Environment=PATH=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

    echo "=== Enabling and starting $SERVICE_NAME service ==="
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl start $SERVICE_NAME
elif [ "$OS_TYPE" == "macos" ]; then
    echo "=== Creating LaunchAgent for macOS ==="
    mkdir -p "$HOME/Library/LaunchAgents"
    cat << EOF > "$HOME/Library/LaunchAgents/com.ollama.interceptor.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ollama.interceptor</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/start-mitmweb.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/error.log</string>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/output.log</string>
</dict>
</plist>
EOF

    echo "=== Loading and starting LaunchAgent ==="
    launchctl load "$HOME/Library/LaunchAgents/com.ollama.interceptor.plist"
    launchctl start com.ollama.interceptor
fi

echo "✅ All done!"
echo "➡ API Proxy available at: http://localhost:$INTERCEPT_PORT/"
echo "➡ Web UI available at: http://localhost:$WEB_UI_PORT/"
echo ""
echo "To change configuration, edit: $INSTALL_DIR/.env"
echo "Then restart the service:"
if [ "$OS_TYPE" == "linux" ]; then
    echo "  sudo systemctl restart $SERVICE_NAME"
else
    echo "  launchctl stop com.ollama.interceptor"
    echo "  launchctl start com.ollama.interceptor"
fi

# Open web UI in the default browser
echo "=== Opening Web UI in browser ==="
if [ "$OS_TYPE" == "linux" ]; then
    # Try various browser opening commands for Linux
    if command -v xdg-open &> /dev/null; then
        xdg-open "http://localhost:$WEB_UI_PORT/" &
    elif command -v gnome-open &> /dev/null; then
        gnome-open "http://localhost:$WEB_UI_PORT/" &
    elif command -v gio &> /dev/null; then
        gio open "http://localhost:$WEB_UI_PORT/" &
    else
        echo "Could not automatically open browser. Please visit http://localhost:$WEB_UI_PORT/ manually."
    fi
elif [ "$OS_TYPE" == "macos" ]; then
    # macOS browser opening command
    open "http://localhost:$WEB_UI_PORT/"
fi

echo "=== Installation Complete ==="
