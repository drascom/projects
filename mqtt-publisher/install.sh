#!/bin/bash

set -e

# === Settings ===
INSTALL_DIR="$HOME/mqtt-publisher"
VENV_DIR="$INSTALL_DIR/venv"
SERVICE_NAME="mqtt-publisher"
REPO_URL="https://github.com/drascom/projects.git"
REPO_DIR="projects"
PROJECT_DIR="mqtt-publisher"

# Parse command line arguments
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
    esac
done

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print colored message
print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

# Execute or simulate a command
execute() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY-RUN:${NC} Would execute: $@"
    else
        "$@"
    fi
}

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
else
    print_error "Unsupported OS: $OSTYPE"
    exit 1
fi

print_message "Detected OS: $OS_TYPE"

# Check if the installation directory already exists
if [ -d "$INSTALL_DIR" ]; then
    print_warning "Installation directory already exists: $INSTALL_DIR"
    read -p "Do you want to remove it and continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "Installation aborted."
        exit 0
    fi
    rm -rf "$INSTALL_DIR"
fi

# Create installation directory
print_message "Creating installation directory: $INSTALL_DIR"
execute mkdir -p "$INSTALL_DIR"

# Install system dependencies
if [ "$OS_TYPE" == "linux" ]; then
    print_message "Installing system dependencies (Linux)"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY-RUN:${NC} Would execute: sudo apt update"
        echo -e "${YELLOW}DRY-RUN:${NC} Would execute: sudo apt install -y python3 python3-pip git curl"
    else
        sudo apt update
        sudo apt install -y python3 python3-pip git curl
    fi
elif [ "$OS_TYPE" == "macos" ]; then
    print_message "Installing system dependencies (macOS)"
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        print_message "Installing Homebrew..."
        if [ "$DRY_RUN" = true ]; then
            echo -e "${YELLOW}DRY-RUN:${NC} Would execute: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        else
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
    fi
    execute brew install python3 git curl
fi

# Install uv
print_message "Installing uv (fast Python package installer)"
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY-RUN:${NC} Would execute: curl -Ls https://astral.sh/uv/install.sh | sh"
else
    curl -Ls https://astral.sh/uv/install.sh | sh
fi

# Add uv to PATH for this session
export PATH="$HOME/.local/bin:$PATH"

# Clone the repository
print_message "Cloning repository from $REPO_URL"
execute cd "$HOME"
if [ -d "$REPO_DIR" ]; then
    print_warning "Repository directory already exists: $REPO_DIR"
    if [ "$DRY_RUN" = false ]; then
        read -p "Do you want to pull the latest changes? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            execute cd "$REPO_DIR"
            execute git pull
            execute cd ..
        fi
    else
        echo -e "${YELLOW}DRY-RUN:${NC} Would prompt user to pull latest changes"
    fi
else
    execute git clone "$REPO_URL" "$REPO_DIR"
fi

# Copy project files to installation directory
print_message "Copying project files to $INSTALL_DIR"
execute cp -r "$HOME/$REPO_DIR/$PROJECT_DIR"/* "$INSTALL_DIR/"
execute cp -r "$HOME/$REPO_DIR/shared" "$INSTALL_DIR/"

# Create virtual environment using uv
print_message "Creating virtual environment with uv"
execute uv venv "$VENV_DIR"

# Install dependencies
print_message "Installing dependencies"
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY-RUN:${NC} Would execute: source \"$VENV_DIR/bin/activate\""
    echo -e "${YELLOW}DRY-RUN:${NC} Would execute: uv pip install -r \"$INSTALL_DIR/requirements.txt\""
else
    source "$VENV_DIR/bin/activate"
    uv pip install -r "$INSTALL_DIR/requirements.txt"
fi

# Create .env file if it doesn't exist
if [ ! -f "$INSTALL_DIR/.env" ]; then
    print_message "Creating default .env file"
    execute cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
    print_warning "Please edit $INSTALL_DIR/.env to configure your MQTT settings"
fi

# Create startup script
print_message "Creating startup script"
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY-RUN:${NC} Would create startup script at $INSTALL_DIR/start.sh"
else
    cat > "$INSTALL_DIR/start.sh" << 'EOF'
#!/bin/bash

# Activate virtual environment
source "$(dirname "$0")/venv/bin/activate"

# Run the optimized app
python "$(dirname "$0")/optimized_app.py"
EOF
fi

execute chmod +x "$INSTALL_DIR/start.sh"

# Create service file based on OS
if [ "$OS_TYPE" == "linux" ]; then
    print_message "Creating systemd service"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY-RUN:${NC} Would create systemd service file at /etc/systemd/system/$SERVICE_NAME.service"
        echo -e "${YELLOW}DRY-RUN:${NC} Service file would contain:"
        cat << EOF
[Unit]
Description=MQTT Publisher Service
After=network.target

[Service]
ExecStart=$INSTALL_DIR/start.sh
WorkingDirectory=$INSTALL_DIR
User=$USER
Group=$USER
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    else
        sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null << EOF
[Unit]
Description=MQTT Publisher Service
After=network.target

[Service]
ExecStart=$INSTALL_DIR/start.sh
WorkingDirectory=$INSTALL_DIR
User=$USER
Group=$USER
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    fi

    print_message "Enabling and starting service"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY-RUN:${NC} Would execute: sudo systemctl daemon-reload"
        echo -e "${YELLOW}DRY-RUN:${NC} Would execute: sudo systemctl enable $SERVICE_NAME"
        echo -e "${YELLOW}DRY-RUN:${NC} Would execute: sudo systemctl start $SERVICE_NAME"
        echo -e "${YELLOW}DRY-RUN:${NC} Would execute: sudo systemctl status $SERVICE_NAME --no-pager"
    else
        sudo systemctl daemon-reload
        sudo systemctl enable $SERVICE_NAME
        sudo systemctl start $SERVICE_NAME

        print_message "Service status:"
        sudo systemctl status $SERVICE_NAME --no-pager
    fi

elif [ "$OS_TYPE" == "macos" ]; then
    print_message "Creating LaunchAgent for macOS"
    execute mkdir -p "$HOME/Library/LaunchAgents"

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY-RUN:${NC} Would create LaunchAgent file at $HOME/Library/LaunchAgents/com.user.$SERVICE_NAME.plist"
        echo -e "${YELLOW}DRY-RUN:${NC} LaunchAgent file would contain:"
        cat << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.$SERVICE_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/start.sh</string>
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
    else
        cat > "$HOME/Library/LaunchAgents/com.user.$SERVICE_NAME.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.$SERVICE_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/start.sh</string>
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
    fi

    print_message "Loading and starting LaunchAgent"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY-RUN:${NC} Would execute: launchctl load \"$HOME/Library/LaunchAgents/com.user.$SERVICE_NAME.plist\""
        echo -e "${YELLOW}DRY-RUN:${NC} Would execute: launchctl start \"com.user.$SERVICE_NAME\""
    else
        launchctl load "$HOME/Library/LaunchAgents/com.user.$SERVICE_NAME.plist"
        launchctl start "com.user.$SERVICE_NAME"
    fi
fi

print_message "Installation completed successfully!"
print_message "MQTT Publisher is now installed at: $INSTALL_DIR"
print_message "Configuration file: $INSTALL_DIR/.env"
print_message "Logs:"
if [ "$OS_TYPE" == "linux" ]; then
    echo "  sudo journalctl -u $SERVICE_NAME -f"
elif [ "$OS_TYPE" == "macos" ]; then
    echo "  $INSTALL_DIR/output.log"
    echo "  $INSTALL_DIR/error.log"
fi

print_message "To start/stop the service manually:"
if [ "$OS_TYPE" == "linux" ]; then
    echo "  sudo systemctl start $SERVICE_NAME"
    echo "  sudo systemctl stop $SERVICE_NAME"
    echo "  sudo systemctl restart $SERVICE_NAME"
elif [ "$OS_TYPE" == "macos" ]; then
    echo "  launchctl start com.user.$SERVICE_NAME"
    echo "  launchctl stop com.user.$SERVICE_NAME"
fi

print_message "To run manually:"
echo "  $INSTALL_DIR/start.sh"
