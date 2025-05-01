#!/bin/bash

set -e

# === Settings ===
INSTALL_DIR="$HOME/ollama-interceptor"
VENV_DIR="$INSTALL_DIR/mitmproxy-env"
SERVICE_NAME="mitmweb"
TARGET_URL="http://localhost:11434"
INTERCEPT_PORT=8080

echo "=== Installing system packages ==="
sudo apt update
sudo apt install -y python3 python3-pip python3-venv curl lsof

echo "=== Installing uv (fast environment manager) ==="
curl -Ls https://astral.sh/uv/install.sh | sh
export PATH=$PATH:$HOME/.local/bin
echo 'export PATH=$PATH:$HOME/.local/bin' >> $HOME/.bashrc
source $HOME/.bashrc

echo "=== Creating install directory at $INSTALL_DIR ==="
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

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

# Activate UV environment
if [ -d "\$VENV_DIR" ]; then
    echo "Activating UV environment..."
    source "\$VENV_DIR/bin/activate"
else
    echo "UV environment not found at \$VENV_DIR!"
    exit 1
fi

# Check if port is free
if lsof -i ":\$FIXED_PORT" >/dev/null; then
    echo "❌ ERROR: Port \$FIXED_PORT is already in use. Cannot start mitmweb."
    exit 1
fi

# Start mitmweb
echo "✅ Port \$FIXED_PORT is free. Starting mitmweb..."
echo "Web UI available at http://your-server-ip:8081/"

mitmweb --mode reverse:\${OLLAMA_TARGET}@\${FIXED_PORT} -p \${FIXED_PORT} --web-host 0.0.0.0 -s "\$INSTALL_DIR/ollama_intercept.py"
EOF

chmod +x "$INSTALL_DIR/start-mitmweb.sh"

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

echo "✅ All done!"
echo "➡ API Proxy available at: http://your-server-ip:$INTERCEPT_PORT/"
echo "➡ Web UI available at: http://your-server-ip:8081/"
