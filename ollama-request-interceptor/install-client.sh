#!/bin/bash

set -e

# === Settings ===
INSTALL_DIR="$HOME/ollama-interceptor-client"
CONFIG_FILE="$INSTALL_DIR/client.env"

# Default settings
SERVER_HOST=""
SERVER_WEB_UI_PORT=8081
AUTH_USERNAME=""
AUTH_PASSWORD=""
LOCAL_PORT=8082

echo "=== Ollama Request Interceptor - Client Installation ==="

# Create .env file if it doesn't exist
if [ ! -f client.env ]; then
    echo "Creating default client.env file..."
    cp client.env.example client.env
    echo "Please edit client.env to configure your connection to the server."
    echo "Then run this script again."
    exit 0
fi

# Load environment variables from client.env
if [ -f client.env ]; then
    echo "Loading configuration from client.env file..."
    # Use grep and cut to extract values (more portable than source)
    ENV_SERVER_HOST=$(grep -E '^SERVER_HOST=' client.env | cut -d '=' -f 2-)
    ENV_SERVER_WEB_UI_PORT=$(grep -E '^SERVER_WEB_UI_PORT=' client.env | cut -d '=' -f 2-)
    ENV_AUTH_USERNAME=$(grep -E '^AUTH_USERNAME=' client.env | cut -d '=' -f 2-)
    ENV_AUTH_PASSWORD=$(grep -E '^AUTH_PASSWORD=' client.env | cut -d '=' -f 2-)
    ENV_LOCAL_PORT=$(grep -E '^LOCAL_PORT=' client.env | cut -d '=' -f 2-)
    
    # Override defaults if values are set in client.env
    [ -n "$ENV_SERVER_HOST" ] && SERVER_HOST="$ENV_SERVER_HOST"
    [ -n "$ENV_SERVER_WEB_UI_PORT" ] && SERVER_WEB_UI_PORT="$ENV_SERVER_WEB_UI_PORT"
    [ -n "$ENV_AUTH_USERNAME" ] && AUTH_USERNAME="$ENV_AUTH_USERNAME"
    [ -n "$ENV_AUTH_PASSWORD" ] && AUTH_PASSWORD="$ENV_AUTH_PASSWORD"
    [ -n "$ENV_LOCAL_PORT" ] && LOCAL_PORT="$ENV_LOCAL_PORT"
fi

# Validate configuration
if [ -z "$SERVER_HOST" ]; then
    echo "❌ ERROR: SERVER_HOST is not set in client.env"
    echo "Please edit client.env and set SERVER_HOST to the hostname or IP address of your server."
    exit 1
fi

echo "=== Configuration ==="
echo "Server Host: $SERVER_HOST"
echo "Server Web UI Port: $SERVER_WEB_UI_PORT"
echo "Local Port: $LOCAL_PORT"
if [ -n "$AUTH_USERNAME" ]; then
    echo "Authentication: Enabled"
else
    echo "Authentication: Disabled"
fi

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
else
    OS_TYPE="linux"
fi

echo "=== Detected OS: $OS_TYPE ==="

# Check for SSH
if ! command -v ssh &> /dev/null; then
    echo "❌ ERROR: SSH client not found. Please install SSH."
    if [ "$OS_TYPE" == "linux" ]; then
        echo "Run: sudo apt install openssh-client"
    elif [ "$OS_TYPE" == "macos" ]; then
        echo "SSH should be pre-installed on macOS. If not, install Homebrew and run: brew install openssh"
    fi
    exit 1
fi

# Create installation directory
echo "=== Creating install directory at $INSTALL_DIR ==="
mkdir -p "$INSTALL_DIR"

# Copy client.env to installation directory
echo "=== Copying client.env to installation directory ==="
cp client.env "$CONFIG_FILE"

# Create client connection script
echo "=== Creating client-connect.sh ==="
cat << EOF > "$INSTALL_DIR/client-connect.sh"
#!/bin/bash

INSTALL_DIR="$INSTALL_DIR"
CONFIG_FILE="$CONFIG_FILE"

# Default settings
SERVER_HOST="$SERVER_HOST"
SERVER_WEB_UI_PORT=$SERVER_WEB_UI_PORT
AUTH_USERNAME="$AUTH_USERNAME"
AUTH_PASSWORD="$AUTH_PASSWORD"
LOCAL_PORT=$LOCAL_PORT

# Load environment variables from client.env if it exists
if [ -f "\$CONFIG_FILE" ]; then
    echo "Loading configuration from client.env file..."
    # Use grep and cut to extract values
    ENV_SERVER_HOST=\$(grep -E '^SERVER_HOST=' "\$CONFIG_FILE" | cut -d '=' -f 2-)
    ENV_SERVER_WEB_UI_PORT=\$(grep -E '^SERVER_WEB_UI_PORT=' "\$CONFIG_FILE" | cut -d '=' -f 2-)
    ENV_AUTH_USERNAME=\$(grep -E '^AUTH_USERNAME=' "\$CONFIG_FILE" | cut -d '=' -f 2-)
    ENV_AUTH_PASSWORD=\$(grep -E '^AUTH_PASSWORD=' "\$CONFIG_FILE" | cut -d '=' -f 2-)
    ENV_LOCAL_PORT=\$(grep -E '^LOCAL_PORT=' "\$CONFIG_FILE" | cut -d '=' -f 2-)
    
    # Override defaults if values are set in client.env
    [ -n "\$ENV_SERVER_HOST" ] && SERVER_HOST="\$ENV_SERVER_HOST"
    [ -n "\$ENV_SERVER_WEB_UI_PORT" ] && SERVER_WEB_UI_PORT="\$ENV_SERVER_WEB_UI_PORT"
    [ -n "\$ENV_AUTH_USERNAME" ] && AUTH_USERNAME="\$ENV_AUTH_USERNAME"
    [ -n "\$ENV_AUTH_PASSWORD" ] && AUTH_PASSWORD="\$ENV_AUTH_PASSWORD"
    [ -n "\$ENV_LOCAL_PORT" ] && LOCAL_PORT="\$ENV_LOCAL_PORT"
fi

echo "=== Ollama Request Interceptor - Client Connection ==="
echo "Connecting to server: \$SERVER_HOST"
echo "Server Web UI Port: \$SERVER_WEB_UI_PORT"
echo "Local Port: \$LOCAL_PORT"

# Check if port is free
if command -v lsof &> /dev/null && lsof -i ":\$LOCAL_PORT" >/dev/null; then
    echo "❌ ERROR: Port \$LOCAL_PORT is already in use. Cannot establish SSH tunnel."
    echo "Please edit \$CONFIG_FILE and change LOCAL_PORT to a different value."
    exit 1
fi

# Create SSH tunnel
echo "✅ Port \$LOCAL_PORT is free. Creating SSH tunnel..."
echo "Web UI will be available at http://localhost:\$LOCAL_PORT/"
echo "Press Ctrl+C to disconnect."

# Open browser
if [[ "\$OSTYPE" == "darwin"* ]]; then
    open "http://localhost:\$LOCAL_PORT/"
elif command -v xdg-open &> /dev/null; then
    xdg-open "http://localhost:\$LOCAL_PORT/" &
elif command -v gnome-open &> /dev/null; then
    gnome-open "http://localhost:\$LOCAL_PORT/" &
elif command -v gio &> /dev/null; then
    gio open "http://localhost:\$LOCAL_PORT/" &
else
    echo "Could not automatically open browser. Please visit http://localhost:\$LOCAL_PORT/ manually."
fi

# Create SSH tunnel
ssh -N -L \$LOCAL_PORT:localhost:\$SERVER_WEB_UI_PORT \$SERVER_HOST
EOF

chmod +x "$INSTALL_DIR/client-connect.sh"

echo "✅ Client installation complete!"
echo "➡ To connect to the server, run: $INSTALL_DIR/client-connect.sh"
echo ""
echo "To change configuration, edit: $CONFIG_FILE"

echo "=== Installation Complete ==="
