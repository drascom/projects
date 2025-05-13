#!/bin/bash

set -e

# === Settings ===
INSTALL_DIR="$HOME/mqtt-publisher"
SERVICE_NAME="mqtt-publisher"

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

# Confirm uninstallation
if [ "$DRY_RUN" = false ]; then
    read -p "Are you sure you want to uninstall MQTT Publisher? This will remove all files and stop the service. (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "Uninstallation aborted."
        exit 0
    fi
else
    echo -e "${YELLOW}DRY-RUN:${NC} Would prompt for confirmation before uninstalling"
fi

# Stop and remove service
if [ "$OS_TYPE" == "linux" ]; then
    print_message "Stopping and removing systemd service"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY-RUN:${NC} Would check if service is active and stop it if needed"
        echo -e "${YELLOW}DRY-RUN:${NC} Would check if service is enabled and disable it if needed"
        echo -e "${YELLOW}DRY-RUN:${NC} Would remove service file if it exists"
        echo -e "${YELLOW}DRY-RUN:${NC} Would reload systemd daemon"
    else
        if systemctl is-active --quiet $SERVICE_NAME; then
            sudo systemctl stop $SERVICE_NAME
        fi
        if systemctl is-enabled --quiet $SERVICE_NAME; then
            sudo systemctl disable $SERVICE_NAME
        fi
        if [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
            sudo rm "/etc/systemd/system/$SERVICE_NAME.service"
            sudo systemctl daemon-reload
        fi
    fi
elif [ "$OS_TYPE" == "macos" ]; then
    print_message "Stopping and removing LaunchAgent"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY-RUN:${NC} Would stop LaunchAgent: launchctl stop \"com.user.$SERVICE_NAME\""
        echo -e "${YELLOW}DRY-RUN:${NC} Would unload LaunchAgent: launchctl unload \"$HOME/Library/LaunchAgents/com.user.$SERVICE_NAME.plist\""
        echo -e "${YELLOW}DRY-RUN:${NC} Would remove LaunchAgent file if it exists"
    else
        launchctl stop "com.user.$SERVICE_NAME" 2>/dev/null || true
        launchctl unload "$HOME/Library/LaunchAgents/com.user.$SERVICE_NAME.plist" 2>/dev/null || true
        if [ -f "$HOME/Library/LaunchAgents/com.user.$SERVICE_NAME.plist" ]; then
            rm "$HOME/Library/LaunchAgents/com.user.$SERVICE_NAME.plist"
        fi
    fi
fi

# Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
    print_message "Removing installation directory: $INSTALL_DIR"
    execute rm -rf "$INSTALL_DIR"
else
    print_warning "Installation directory not found: $INSTALL_DIR"
fi

print_message "Uninstallation completed successfully!"
print_message "MQTT Publisher has been removed from your system."

# Ask if user wants to keep the repository
if [ "$DRY_RUN" = false ]; then
    read -p "Do you want to keep the repository in $HOME/projects? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        if [ -d "$HOME/projects" ]; then
            print_message "Removing repository directory: $HOME/projects"
            execute rm -rf "$HOME/projects"
        fi
    fi
else
    echo -e "${YELLOW}DRY-RUN:${NC} Would prompt user about keeping the repository"
    echo -e "${YELLOW}DRY-RUN:${NC} Would potentially remove $HOME/projects if user chooses not to keep it"
fi
