#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  MQTT Device Monitor unified management script
#  Modes:  install (default), uninstall, reconfigure, help
#
#  One‑liner remote install (Linux/macOS):
#    curl -fsSL https://raw.githubusercontent.com/drascom/mqtt-device-monitor/main/manage.sh | bash
#    # add sudo before bash on Linux if you want it to install system packages
#
#  Or download and run locally (script will make itself executable):
#    curl -fsSL https://raw.githubusercontent.com/drascom/mqtt-device-monitor/main/manage.sh -o manage.sh
#    ./manage.sh
# ---------------------------------------------------------------------------
set -uo pipefail  # Removed 'e' to prevent unexpected exits
IFS=$'\n\t'

# Add trap to catch unexpected exits
trap 'echo "Script exited unexpectedly at line $LINENO. Last command: $BASH_COMMAND"' ERR

# Make this script executable if it's not already
if [[ ! -x "$0" && "$0" != "bash" ]]; then
  echo "Making this script executable..."
  chmod +x "$0"
fi

# ─── Colours ────────────────────────────────────────────────────────────────
RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; NC="\033[0m"
print_msg() { local c="${2:-$GREEN}"; printf "%b%s%b\n" "$c" "$1" "$NC"; }

# ─── Helpers ────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" &>/dev/null; }
ACTUAL_USER=${SUDO_USER:-$(whoami)}
run_as_user() { [[ $(whoami) == "$ACTUAL_USER" ]] && "$@" || sudo -u "$ACTUAL_USER" "$@"; }
require_root()  { [[ $(id -u) -eq 0 ]] || { print_msg "This action must be run as root" "$RED"; exit 1; }; }
ask_yn()        {
                 local msg=$1 def=${2:-false} prompt="[y/N]"; [[ $def == true ]] && prompt="[Y/n]"
                 echo -n "$msg $prompt "
                 read -r ans </dev/tty
                 ans=${ans:-$([[ $def == true ]] && echo y || echo n)}
                 # Use tr for case insensitive comparison (more compatible than ${ans,,})
                 [[ $(echo "$ans" | tr '[:upper:]' '[:lower:]') == y* ]];
                }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--uninstall|--reconfigure|--help]

  --uninstall     Stop & remove the service, optionally delete files
  --reconfigure   Re‑run the .env wizard and restart the service
  --help          Show this help

With no flag it installs / updates the application.
EOF
}

# ─── OS detection ───────────────────────────────────────────────────────────
OS=""; DISTRO=""
detect_os() {
  # Add debugging output
  print_msg "Detecting operating system..." "$BLUE"

  # Get OS type with error handling
  local os_type
  os_type=$(uname -s 2>/dev/null) || {
    print_msg "Failed to execute 'uname -s'" "$RED"
    print_msg "Trying alternative detection methods..." "$YELLOW"

    # Try alternative detection methods
    if [[ -f /proc/version ]]; then
      if grep -qi "linux" /proc/version; then
        os_type="Linux"
      fi
    elif [[ -d /System/Library/CoreServices ]]; then
      os_type="Darwin"
    fi

    # If still no detection, try a simple check
    if [[ -z "$os_type" ]]; then
      if [[ "$(uname 2>/dev/null)" == "Darwin" ]]; then
        os_type="Darwin"
      elif [[ "$(uname 2>/dev/null)" == "Linux" ]]; then
        os_type="Linux"
      fi
    fi

    # If all else fails
    if [[ -z "$os_type" ]]; then
      print_msg "Could not detect OS type" "$RED"
      return 1
    fi
  }

  print_msg "Detected system type: $os_type" "$GREEN"

  # Set OS based on detected type
  case "$os_type" in
    Darwin*)
      OS="macos"
      print_msg "Identified as macOS" "$GREEN"
      ;;
    Linux*)
      OS="linux"
      print_msg "Identified as Linux" "$GREEN"
      ;;
    *)
      print_msg "Unsupported OS: $os_type" "$RED"
      return 1
      ;;
  esac

  # For Linux, detect distribution
  if [[ $OS == "linux" ]]; then
    if [[ -e /etc/os-release ]]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      DISTRO=$ID
      print_msg "Linux distribution: $DISTRO" "$GREEN"
    else
      print_msg "Could not detect Linux distribution" "$YELLOW"
      DISTRO="unknown"
    fi
  fi

  return 0
}

# ─── Globals ────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/mqtt-device-monitor"
PYTHON="python3"
REPO_URL="https://github.com/drascom/mqtt-device-monitor.git"
SYSTEMD_UNIT="/etc/systemd/system/mqtt-device-monitor@.service"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.mqtt-device-monitor.plist"
GUI_PORT=9876        # overwritten by wizard

# ─── System packages ────────────────────────────────────────────────────────
install_system_deps() {
  print_msg "Installing system dependencies …" "$BLUE"
  if [[ $OS == linux ]]; then
    require_root
    case $DISTRO in
      ubuntu|debian)
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y git curl build-essential mosquitto "$PYTHON" "$PYTHON"-venv pipx uv || true
        ;;
      arch)
        pacman -Sy --noconfirm git curl base-devel mosquitto "$PYTHON" python-virtualenv python-pipx uv || true
        ;;
      *)
        print_msg "Unknown distro – please install git, curl, python3, mosquitto, pipx, uv manually." "$YELLOW"
        ;;
    esac
  else
    if ! command_exists brew; then
      print_msg "Homebrew not found – installing (may prompt for password)" "$YELLOW"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv || /usr/local/bin/brew shellenv)"
    fi
    brew install git mosquitto python3 pipx uv || true
  fi
}

# ─── Repository ─────────────────────────────────────────────────────────────
fetch_repo() {
  print_msg "Fetching repository …" "$BLUE"

  # Check if installation directory exists and delete it for a clean installation
  if [[ -d "$INSTALL_DIR" ]]; then
    print_msg "Installation directory already exists: $INSTALL_DIR" "$YELLOW"
    print_msg "Removing existing directory for a clean installation..." "$YELLOW"

    # Try to delete the directory
    if ! run_as_user rm -rf "$INSTALL_DIR"; then
      print_msg "Failed to remove existing installation directory" "$RED"
      print_msg "Please manually remove the directory and try again:" "$RED"
      print_msg "  rm -rf $INSTALL_DIR" "$RED"
      return 1
    fi

    print_msg "Existing installation directory removed successfully" "$GREEN"
  fi

  # Create a fresh installation directory
  print_msg "Creating installation directory: $INSTALL_DIR" "$BLUE"
  if ! run_as_user mkdir -p "$INSTALL_DIR"; then
    print_msg "Failed to create installation directory: $INSTALL_DIR" "$RED"
    return 1
  fi

  # Clone the repository
  print_msg "Cloning into $INSTALL_DIR" "$BLUE"
  if ! run_as_user git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
    print_msg "Git clone failed" "$RED"
    return 1
  fi

  # Verify that we have the required files
  if [[ ! -f "$INSTALL_DIR/main.py" ]]; then
    print_msg "Repository files are missing or incomplete" "$RED"
    return 1
  fi

  # Make manage.sh executable
  if [[ -f "$INSTALL_DIR/manage.sh" ]]; then
    print_msg "Making manage.sh executable..." "$BLUE"
    run_as_user chmod +x "$INSTALL_DIR/manage.sh"
    print_msg "manage.sh is now executable" "$GREEN"
  else
    print_msg "Warning: manage.sh not found in repository" "$YELLOW"
  fi

  print_msg "Repository fetched successfully" "$GREEN"
  return 0
}

# ─── Virtual environment (uv) ───────────────────────────────────────────────
create_virtual_env() {
  print_msg "Creating Python virtual environment with uv …" "$BLUE"

  # Check if the installation directory exists
  if [[ ! -d "$INSTALL_DIR" ]]; then
    print_msg "Installation directory not found: $INSTALL_DIR" "$RED"
    print_msg "Repository fetch may have failed" "$RED"
    return 1
  fi

  # Change to the installation directory
  if ! cd "$INSTALL_DIR" 2>/dev/null; then
    print_msg "Cannot access installation directory: $INSTALL_DIR" "$RED"
    print_msg "Check permissions and try again" "$RED"
    return 1
  fi

  print_msg "Working directory: $(pwd)" "$BLUE"

  # Check if uv is available using uv --version
  if ! uv --version &>/dev/null; then
    print_msg "uv not found – installing via pipx" "$YELLOW"

    # Install pipx if needed
    local PIPX_COMMAND="pipx"
    if ! command_exists pipx; then
      print_msg "pipx not found – installing" "$YELLOW"
      "$PYTHON" -m pip install --user --upgrade pipx
      "$PYTHON" -m pipx ensurepath
      export PATH="$HOME/.local/bin:$PATH"

      # Check if pipx is now in PATH, otherwise use full path
      if [[ -f "$HOME/.local/bin/pipx" ]]; then
        PIPX_COMMAND="$HOME/.local/bin/pipx"
        print_msg "Using pipx at $PIPX_COMMAND" "$GREEN"
      elif [[ -f "/usr/local/bin/pipx" ]]; then
        PIPX_COMMAND="/usr/local/bin/pipx"
        print_msg "Using pipx at $PIPX_COMMAND" "$GREEN"
      fi
    fi

    # Install uv using pipx or pip
    run_as_user "$PIPX_COMMAND" install --force uv || {
      print_msg "pipx failed – installing uv via pip" "$YELLOW"
      run_as_user "$PYTHON" -m pip install --user --upgrade uv
    }

    # Verify uv is now in PATH and accessible
    if [[ -f "$HOME/.local/bin/uv" ]]; then
      export PATH="$HOME/.local/bin:$PATH"
      print_msg "Added uv to PATH" "$GREEN"
    elif [[ -f "/usr/local/bin/uv" ]]; then
      export PATH="/usr/local/bin:$PATH"
      print_msg "Added uv to PATH" "$GREEN"
    fi

    # Verify uv is now accessible
    if ! uv --version &>/dev/null; then
      print_msg "uv installation succeeded but command not found in PATH" "$YELLOW"
      print_msg "Trying to locate uv binary..." "$BLUE"
      UV_PATH=$(find "$HOME/.local" /usr/local -name uv -type f 2>/dev/null | head -1)
      if [[ -n "$UV_PATH" ]]; then
        print_msg "Found uv at $UV_PATH" "$GREEN"
        export PATH="$(dirname "$UV_PATH"):$PATH"
      else
        print_msg "Could not locate uv binary" "$RED"
      fi
    fi
  fi

  # Check if uv is now available and get its path
  local UV_COMMAND=""
  if uv --version &>/dev/null; then
    UV_COMMAND="uv"
  elif [[ -f "$HOME/.local/bin/uv" ]]; then
    UV_COMMAND="$HOME/.local/bin/uv"
  elif [[ -f "/usr/local/bin/uv" ]]; then
    UV_COMMAND="/usr/local/bin/uv"
  else
    # Try to find uv in PATH
    UV_COMMAND=$(which uv 2>/dev/null || echo "")
  fi

  if [[ -n "$UV_COMMAND" ]]; then
    # Build venv with uv (idempotent)
    print_msg "Using uv to create virtual environment" "$BLUE"
    # Use correct syntax for uv venv (without --seed pip)
    run_as_user "$UV_COMMAND" venv .venv || true
  elif command_exists pyenv; then
    # Fallback to pyenv if available
    print_msg "uv not available - falling back to pyenv" "$YELLOW"
    run_as_user pyenv virtualenv 3.10 mqtt-monitor-env || true
    run_as_user ln -sf "$(pyenv prefix mqtt-monitor-env)" .venv
  else
    # Fallback to standard venv
    print_msg "uv and pyenv not available - falling back to standard venv" "$YELLOW"
    run_as_user "$PYTHON" -m venv .venv
  fi

  # Ensure Python and pip are available in the virtual environment
  [[ -x .venv/bin/python ]] || { print_msg "Virtual env creation failed - falling back to python -m venv" "$YELLOW"; run_as_user "$PYTHON" -m venv .venv; }
  [[ -x .venv/bin/pip ]]   || run_as_user .venv/bin/python -m ensurepip --upgrade
  print_msg "Virtual environment ready" "$GREEN"

  # Install Python requirements
  if [[ -f requirements.txt ]]; then
    print_msg "Installing Python requirements..." "$BLUE"
    if [[ -n "$UV_COMMAND" ]]; then
      # Use uv for faster package installation if available
      print_msg "Using uv for package installation" "$GREEN"
      run_as_user "$UV_COMMAND" pip install -r requirements.txt || run_as_user .venv/bin/pip install -r requirements.txt
    else
      # Fall back to regular pip
      run_as_user .venv/bin/pip install -r requirements.txt
    fi
    print_msg "Python requirements installed" "$GREEN"
  fi
}

# ─── .env configuration wizard ─────────────────────────────────────────────
interactive_config() {
  print_msg "Creating / updating .env" "$BLUE"
  local env_file="$INSTALL_DIR/.env"

  # Check if the installation directory exists
  if [[ ! -d "$INSTALL_DIR" ]]; then
    print_msg "Installation directory not found: $INSTALL_DIR" "$RED"
    print_msg "Repository fetch may have failed" "$RED"
    return 1
  fi

  # Change to the installation directory
  if ! cd "$INSTALL_DIR" 2>/dev/null; then
    print_msg "Cannot access installation directory: $INSTALL_DIR" "$RED"
    print_msg "Check permissions and try again" "$RED"
    return 1
  fi

  print_msg "Working directory: $(pwd)" "$BLUE"

  # Set default values
  local default_broker="localhost"
  local broker=""
  local port="9001"
  local mqtt_user=""
  local mqtt_pass=""
  local gui_port="9876"
  local device_id=$(hostname)

  print_msg "Starting interactive configuration..." "$BLUE"

  # Simple check for Mosquitto - just check if the command exists
  if command_exists mosquitto; then
    print_msg "Mosquitto found in PATH - using 'localhost' as default" "$GREEN"
    default_broker="localhost"
  else
    print_msg "Mosquitto not found in PATH" "$YELLOW"
    default_broker="remote.host"
  fi

  # Prompt for broker address - use read with prompt
  print_msg "Enter MQTT broker address:" "$BLUE"
  echo -n "MQTT broker [$default_broker]: "
  read -r broker </dev/tty
  broker=${broker:-$default_broker}
  print_msg "Using broker: $broker" "$GREEN"

  # MQTT port
  print_msg "Enter MQTT port:" "$BLUE"
  echo -n "MQTT port [9001]: "
  read -r port </dev/tty
  port=${port:-9001}
  print_msg "Using port: $port" "$GREEN"

  # Credentials
  print_msg "MQTT authentication (press Enter to skip)" "$BLUE"
  echo -n "MQTT username (leave blank for none): "
  read -r mqtt_user </dev/tty

  # Only ask for password if username is provided
  mqtt_pass=""
  if [[ -n "$mqtt_user" ]]; then
    echo -n "MQTT password (leave blank for none): "
    read -rs mqtt_pass </dev/tty
    echo  # Add a newline after password input
    print_msg "Authentication configured" "$GREEN"
  else
    print_msg "No authentication configured" "$YELLOW"
  fi

  # GUI port
  print_msg "Enter GUI port:" "$BLUE"
  echo -n "GUI port [9876]: "
  read -r gui_port </dev/tty
  gui_port=${gui_port:-9876}
  print_msg "Using GUI port: $gui_port" "$GREEN"

  # Update global GUI_PORT for final splash message
  GUI_PORT=$gui_port

  # Write the .env file
  print_msg "Writing .env file..." "$BLUE"

  # Create the content first
  local env_content="# Common MQTT settings
MQTT_BROKER=$broker
MQTT_PORT=$port
MQTT_USERNAME=$mqtt_user
MQTT_PASSWORD=$mqtt_pass
MQTT_DEBUG=False

# MQTT client settings
DEVICE_ID=$device_id
MQTT_INTERVAL=5
MQTT_VERSION=3.1.1
MQTT_KEEPALIVE=60

# GUI settings
GUI_HOST=0.0.0.0
GUI_PORT=$gui_port"

  # Write to file - use run_as_user to ensure proper permissions
  print_msg "Writing .env file with proper permissions..." "$BLUE"
  run_as_user bash -c "cat > \"$env_file\"" <<< "$env_content"

  # Verify the file was created
  if [[ ! -f "$env_file" ]]; then
    print_msg "Failed to create .env file" "$RED"
    return 1
  fi

  # Make sure the file has the correct permissions
  run_as_user chmod 600 "$env_file"

  print_msg ".env written to $env_file" "$GREEN"
  print_msg "Configuration complete" "$GREEN"
}

# ─── Service management ────────────────────────────────────────────────────
create_service() {
  print_msg "Creating and enabling background service …" "$BLUE"

  # Make sure the installation directory exists
  if [[ ! -d "$INSTALL_DIR" ]]; then
    print_msg "Installation directory not found, creating it..." "$YELLOW"
    run_as_user mkdir -p "$INSTALL_DIR"
  fi

  # Make sure the virtual environment exists
  if [[ ! -d "$INSTALL_DIR/.venv" ]]; then
    print_msg "Virtual environment not found, it may not have been created properly" "$YELLOW"
    print_msg "Will continue anyway, but service might not start" "$YELLOW"
  fi

  # Double-check if service exists and remove it
  if check_service_exists; then
    print_msg "Existing service detected during service creation" "$YELLOW"
    print_msg "Removing existing service before creating a new one..." "$YELLOW"
    remove_service
  fi

  # Create the service based on OS
  if [[ $OS == linux ]]; then
    print_msg "Creating systemd service for Linux..." "$BLUE"

    # Check if we have root permissions
    if [[ $(id -u) -ne 0 ]]; then
      print_msg "Root permissions required to create systemd service" "$YELLOW"
      print_msg "You may need to run this script with sudo" "$YELLOW"
      print_msg "Skipping service creation" "$RED"
      return 1
    fi

    # Create systemd service file
    print_msg "Writing systemd service file..." "$BLUE"
    tee "$SYSTEMD_UNIT" >/dev/null <<'SERVICE'
[Unit]
Description=MQTT Device Monitor
After=network.target

[Service]
Type=simple
User=%i
WorkingDirectory=%h/mqtt-device-monitor
ExecStart=%h/mqtt-device-monitor/.venv/bin/python %h/mqtt-device-monitor/main.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICE

    # Reload systemd and enable service
    print_msg "Reloading systemd daemon..." "$BLUE"
    systemctl daemon-reload || { print_msg "Failed to reload systemd daemon" "$RED"; return 1; }

    print_msg "Enabling and starting service..." "$BLUE"
    systemctl enable --now "mqtt-device-monitor@$ACTUAL_USER.service" || {
      print_msg "Failed to enable/start service" "$RED"
      print_msg "You can try starting it manually with: sudo systemctl start mqtt-device-monitor@$ACTUAL_USER.service" "$YELLOW"
      return 1
    }

    print_msg "Service created and started successfully" "$GREEN"
  else
    print_msg "Creating launchd service for macOS..." "$BLUE"

    # Create launchd plist file
    print_msg "Writing launchd plist file..." "$BLUE"
    tee "$LAUNCHD_PLIST" >/dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.mqtt-device-monitor</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_DIR/.venv/bin/python</string>
    <string>$INSTALL_DIR/main.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>WorkingDirectory</key><string>$INSTALL_DIR</string>
  <key>StandardOutPath</key><string>$INSTALL_DIR/out.log</string>
  <key>StandardErrorPath</key><string>$INSTALL_DIR/error.log</string>
</dict>
</plist>
PLIST

    # Unload existing service if it exists
    print_msg "Unloading existing service if present..." "$BLUE"
    run_as_user launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true

    # Load the service
    print_msg "Loading service..." "$BLUE"
    if run_as_user launchctl load -w "$LAUNCHD_PLIST"; then
      print_msg "Service created and started successfully" "$GREEN"
    else
      print_msg "Failed to load service" "$RED"
      print_msg "You can try starting it manually with: launchctl load -w $LAUNCHD_PLIST" "$YELLOW"
      return 1
    fi
  fi

  print_msg "Service setup complete" "$GREEN"

  # Provide instructions for service management
  if [[ $OS == linux ]]; then
    print_msg "Service management commands:" "$BLUE"
    print_msg "  Start:  sudo systemctl start mqtt-device-monitor@$ACTUAL_USER.service" "$GREEN"
    print_msg "  Stop:   sudo systemctl stop mqtt-device-monitor@$ACTUAL_USER.service" "$GREEN"
    print_msg "  Status: sudo systemctl status mqtt-device-monitor@$ACTUAL_USER.service" "$GREEN"
  else
    print_msg "Service management commands:" "$BLUE"
    print_msg "  Start:  launchctl load -w $LAUNCHD_PLIST" "$GREEN"
    print_msg "  Stop:   launchctl unload $LAUNCHD_PLIST" "$GREEN"
    print_msg "  Status: launchctl list | grep mqtt-device-monitor" "$GREEN"
  fi
}

check_service_exists() {
  # Check if the service already exists
  if [[ $OS == linux ]]; then
    if systemctl list-unit-files | grep -q "mqtt-device-monitor@$ACTUAL_USER.service"; then
      return 0  # Service exists
    else
      return 1  # Service does not exist
    fi
  else
    if [[ -f "$LAUNCHD_PLIST" ]]; then
      return 0  # Service exists
    else
      return 1  # Service does not exist
    fi
  fi
}

remove_service() {
  print_msg "Removing service …" "$BLUE"

  # Handle Linux systems
  if [[ $OS == linux ]]; then
    print_msg "Removing Linux systemd service..." "$BLUE"

    # Check if we have root permissions
    if [[ $(id -u) -ne 0 ]]; then
      print_msg "Root permissions required to remove systemd service" "$YELLOW"
      print_msg "Attempting to use sudo..." "$YELLOW"

      # Try to use sudo if available
      if command_exists sudo; then
        print_msg "Using sudo to remove service" "$BLUE"
        sudo systemctl disable --now "mqtt-device-monitor@$ACTUAL_USER.service" 2>/dev/null || true
        sudo rm -f "$SYSTEMD_UNIT" 2>/dev/null || true
        sudo systemctl daemon-reload 2>/dev/null || true
      else
        print_msg "sudo not available - cannot remove systemd service" "$RED"
        print_msg "Please run this command as root to properly remove the service" "$RED"
      fi
    else
      # We have root, proceed normally
      systemctl disable --now "mqtt-device-monitor@$ACTUAL_USER.service" 2>/dev/null || true
      rm -f "$SYSTEMD_UNIT" 2>/dev/null || true
      systemctl daemon-reload 2>/dev/null || true
    fi
  else
    # Handle macOS systems
    print_msg "Removing macOS launchd service..." "$BLUE"

    # Check if launchd plist exists
    if [[ -f "$LAUNCHD_PLIST" ]]; then
      print_msg "Found launchd plist at $LAUNCHD_PLIST" "$GREEN"
      run_as_user launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
      run_as_user rm -f "$LAUNCHD_PLIST" 2>/dev/null || true
    else
      print_msg "No launchd plist found at $LAUNCHD_PLIST" "$YELLOW"

      # Try to find the plist in common locations
      local found_plist=$(run_as_user find "$HOME/Library/LaunchAgents" -name "*mqtt*" -type f 2>/dev/null | head -1)

      if [[ -n "$found_plist" ]]; then
        print_msg "Found alternative plist at $found_plist" "$GREEN"
        run_as_user launchctl unload "$found_plist" 2>/dev/null || true
        run_as_user rm -f "$found_plist" 2>/dev/null || true
      fi
    fi
  fi

  print_msg "Service removal attempted" "$GREEN"
  print_msg "If you still see the service running, you may need to remove it manually" "$YELLOW"
}

# ─── Workflows ─────────────────────────────────────────────────────────────
install_workflow() {
  print_msg "Starting installation workflow..." "$BLUE"

  # Step 1: Detect OS
  print_msg "Step 1: Detecting OS..." "$BLUE"
  if ! detect_os; then
    print_msg "OS detection failed" "$RED"
    print_msg "Attempting to determine OS manually..." "$YELLOW"

    # Manual OS detection as fallback
    if [[ -d /System/Library/CoreServices ]]; then
      OS="macos"
      print_msg "Manually detected macOS" "$GREEN"
    elif [[ -d /proc ]]; then
      OS="linux"
      print_msg "Manually detected Linux" "$GREEN"

      # Try to determine Linux distribution
      if [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
      elif [[ -f /etc/arch-release ]]; then
        DISTRO="arch"
      elif [[ -f /etc/fedora-release ]]; then
        DISTRO="fedora"
      else
        DISTRO="unknown"
      fi
      print_msg "Linux distribution (best guess): $DISTRO" "$YELLOW"
    else
      print_msg "Could not determine OS even with fallback methods" "$RED"
      print_msg "Please check if your OS is supported" "$YELLOW"
      print_msg "Supported OS: macOS, Linux" "$YELLOW"
      exit 1
    fi
  fi
  print_msg "OS detected: $OS" "$GREEN"

  # Step 1.5: Check if service exists and remove it
  if check_service_exists; then
    print_msg "Existing service detected" "$YELLOW"
    print_msg "Removing existing service before installation..." "$YELLOW"
    remove_service
  fi

  # Step 2: Install system dependencies
  print_msg "Step 2: Installing system dependencies..." "$BLUE"
  if ! install_system_deps; then
    print_msg "System dependencies installation had issues" "$YELLOW"
    print_msg "Continuing anyway, but some features might not work" "$YELLOW"
  else
    print_msg "System dependencies installed" "$GREEN"
  fi

  # Step 3: Fetch repository
  print_msg "Step 3: Fetching repository..." "$BLUE"
  if ! fetch_repo; then
    print_msg "Repository fetch had issues" "$YELLOW"
    print_msg "Continuing anyway, but using existing files" "$YELLOW"
  else
    print_msg "Repository fetched" "$GREEN"
  fi

  # Step 4: Create virtual environment
  print_msg "Step 4: Creating virtual environment..." "$BLUE"
  if ! create_virtual_env; then
    print_msg "Virtual environment creation had issues" "$YELLOW"
    print_msg "Continuing anyway, but service might not start" "$YELLOW"
  else
    print_msg "Virtual environment created" "$GREEN"
  fi

  # Step 5: Configure environment variables
  print_msg "Step 5: Configuring environment variables..." "$BLUE"
  if ! interactive_config; then
    print_msg "Environment configuration had issues" "$RED"
    print_msg "This is a critical step, cannot continue" "$RED"
    exit 1
  fi
  print_msg "Environment variables configured" "$GREEN"

  # Step 6: Create service
  print_msg "Step 6: Creating service..." "$BLUE"
  if ! create_service; then
    print_msg "Service creation had issues" "$YELLOW"
    print_msg "You may need to start the service manually" "$YELLOW"
  else
    print_msg "Service created" "$GREEN"
  fi

  # Determine local IP (best effort)
  print_msg "Determining local IP address..." "$BLUE"
  local ip="localhost"
  if [[ $OS == macos ]]; then
    ip=$(ipconfig getifaddr en0 2>/dev/null || echo "localhost")
  elif command_exists hostname; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z $ip ]] && ip="localhost"
  fi

  # Final success message
  print_msg "=============================================" "$GREEN"
  print_msg "Installation complete!" "$GREEN"
  print_msg "Access the web GUI at: http://$ip:$GUI_PORT" "$GREEN"
  print_msg "=============================================" "$GREEN"
}

uninstall_workflow() {
  print_msg "Starting uninstall workflow..." "$BLUE"

  # Detect OS with error handling
  if ! detect_os; then
    print_msg "OS detection failed during uninstall" "$RED"
    print_msg "Will attempt to continue with best-effort uninstall" "$YELLOW"

    # Try to determine OS manually for uninstall
    if [[ -d /System/Library/CoreServices ]]; then
      OS="macos"
      print_msg "Manually detected macOS for uninstall" "$GREEN"
    else
      OS="linux"  # Default to Linux if unsure
      print_msg "Defaulting to Linux for uninstall" "$YELLOW"
    fi
  fi

  ask_yn "This will stop the service and optionally delete $INSTALL_DIR. Continue?" false || exit 0

  # Try to remove service even if OS detection failed
  print_msg "Attempting to remove service..." "$BLUE"
  remove_service

  if ask_yn "Delete $INSTALL_DIR directory as well?" false; then
    print_msg "Removing installation directory..." "$BLUE"
    run_as_user rm -rf "$INSTALL_DIR"
    print_msg "Installation directory removed" "$GREEN"
  fi

  print_msg "Uninstall complete" "$GREEN"
}

reconfigure_workflow() {
  print_msg "Starting reconfiguration workflow..." "$BLUE"

  # Detect OS with error handling
  if ! detect_os; then
    print_msg "OS detection failed during reconfiguration" "$RED"
    print_msg "Will attempt to continue with best-effort reconfiguration" "$YELLOW"

    # Try to determine OS manually for reconfiguration
    if [[ -d /System/Library/CoreServices ]]; then
      OS="macos"
      print_msg "Manually detected macOS for reconfiguration" "$GREEN"
    else
      OS="linux"  # Default to Linux if unsure
      print_msg "Defaulting to Linux for reconfiguration" "$YELLOW"
    fi
  fi

  # Fetch repository
  print_msg "Fetching latest repository files..." "$BLUE"
  if ! fetch_repo; then
    print_msg "Repository fetch had issues" "$YELLOW"
    print_msg "Continuing with existing files" "$YELLOW"
  fi

  # Run configuration wizard
  print_msg "Running configuration wizard..." "$BLUE"
  interactive_config

  # Restart service based on detected OS
  print_msg "Restarting service..." "$BLUE"
  if [[ $OS == linux ]]; then
    if command_exists systemctl; then
      sudo systemctl restart "mqtt-device-monitor@$ACTUAL_USER.service" || {
        print_msg "Failed to restart service via systemctl" "$RED"
        print_msg "You may need to restart the service manually" "$YELLOW"
      }
    else
      print_msg "systemctl not found - cannot restart service automatically" "$RED"
      print_msg "Please restart the service manually" "$YELLOW"
    fi
  else
    if command_exists launchctl; then
      run_as_user launchctl kickstart -k gui/$(id -u)/com.mqtt-device-monitor || {
        print_msg "Failed to restart service via launchctl" "$RED"
        print_msg "Try manually with: launchctl unload $LAUNCHD_PLIST && launchctl load -w $LAUNCHD_PLIST" "$YELLOW"
      }
    else
      print_msg "launchctl not found - cannot restart service automatically" "$RED"
      print_msg "Please restart the service manually" "$YELLOW"
    fi
  fi

  print_msg "Reconfiguration complete – service restarted." "$GREEN"
}

# ─── CLI parsing ────────────────────────────────────────────────────────────
MODE="install"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall)       MODE="uninstall" ;;
    --reconfigure)     MODE="reconfigure" ;;
    --help|-h)         usage; exit 0 ;;
    *) print_msg "Unknown option: $1" "$RED"; usage; exit 1 ;;
  esac
  shift
done

# ─── Dispatch ───────────────────────────────────────────────────────────────
case "$MODE" in
  install)     install_workflow ;;
  uninstall)   uninstall_workflow ;;
  reconfigure) reconfigure_workflow ;;
esac
