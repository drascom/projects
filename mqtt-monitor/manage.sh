#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  MQTT Device Monitor unified management script
#  Modes:  install (default), uninstall, reconfigure, help
#
#  One‑liner remote install (Linux/macOS):
#    curl -fsSL https://raw.githubusercontent.com/drascom/projects/main/mqtt-monitor/manage.sh | bash
#    # add sudo before bash on Linux if you want it to install system packages
#
#  Or download and run locally (script will make itself executable):
#    curl -fsSL https://raw.githubusercontent.com/drascom/projects/main/mqtt-monitor/manage.sh -o manage.sh
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
REPO_URL="https://github.com/drascom/projects.git"
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
        # Full system update
        print_msg "Updating system packages..." "$BLUE"
        apt-get update -y
        apt-get upgrade -y

        # Install required packages
        print_msg "Installing required packages..." "$BLUE"
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
    # macOS-specific installation
    print_msg "Installing macOS dependencies..." "$BLUE"

    # Check for Homebrew and install if needed
    if ! command_exists brew; then
      print_msg "Homebrew not found – installing (may prompt for password)" "$YELLOW"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

      # Add Homebrew to PATH based on architecture
      if [[ -d "/opt/homebrew/bin" ]]; then
        # Apple Silicon (M1/M2)
        eval "$(/opt/homebrew/bin/brew shellenv)"
        export PATH="/opt/homebrew/bin:$PATH"
      elif [[ -d "/usr/local/bin" ]]; then
        # Intel Mac
        eval "$(/usr/local/bin/brew shellenv)"
        export PATH="/usr/local/bin:$PATH"
      fi

      print_msg "Homebrew installed and added to PATH" "$GREEN"
    fi

    # Install required packages
    print_msg "Installing required packages with Homebrew..." "$BLUE"
    brew install git mosquitto python3 pipx uv || true

    # Check if osx-cpu-temp is needed for temperature monitoring
    if ! command_exists osx-cpu-temp; then
      print_msg "Installing osx-cpu-temp for macOS temperature monitoring..." "$BLUE"
      brew install osx-cpu-temp || true
    fi

    # Start Mosquitto service if installed
    if command_exists mosquitto && brew services list | grep -q mosquitto; then
      print_msg "Starting Mosquitto MQTT broker..." "$BLUE"
      brew services start mosquitto || true
    fi

    # Verify Python installation
    if command_exists python3; then
      PYTHON_VERSION=$(python3 --version 2>&1)
      print_msg "Python detected: $PYTHON_VERSION" "$GREEN"
    else
      print_msg "Python not found after installation - there may be issues" "$RED"
    fi

    # Verify uv installation
    if command_exists uv; then
      UV_VERSION=$(uv --version 2>&1)
      print_msg "uv detected: $UV_VERSION" "$GREEN"
    else
      print_msg "uv not found after installation - will try alternative methods later" "$YELLOW"
    fi
  fi
}

# ─── Mosquitto MQTT broker configuration ─────────────────────────────────────────
configure_mosquitto() {
  print_msg "Checking Mosquitto MQTT broker installation..." "$BLUE"

  # Check if Mosquitto is installed
  if ! command_exists mosquitto; then
    print_msg "Mosquitto MQTT broker is not installed" "$YELLOW"

    if ask_yn "Would you like to install Mosquitto MQTT broker?" true; then
      print_msg "Installing Mosquitto MQTT broker..." "$BLUE"

      if [[ $OS == linux ]]; then
        require_root
        case $DISTRO in
          ubuntu|debian)
            # Update package lists
            print_msg "Updating package lists..." "$BLUE"
            apt-get update -y

            # Install Mosquitto and clients
            print_msg "Installing Mosquitto and clients..." "$BLUE"
            DEBIAN_FRONTEND=noninteractive apt-get install -y mosquitto mosquitto-clients || true
            ;;
          arch)
            pacman -Sy --noconfirm mosquitto || true
            ;;
          *)
            print_msg "Unknown distro – please install mosquitto manually." "$YELLOW"
            return 1
            ;;
        esac
      else
        # macOS installation via Homebrew
        if command_exists brew; then
          brew install mosquitto || true
        else
          print_msg "Homebrew not found - cannot install Mosquitto" "$RED"
          return 1
        fi
      fi

      # Verify installation
      if ! command_exists mosquitto; then
        print_msg "Failed to install Mosquitto" "$RED"
        return 1
      fi

      print_msg "Mosquitto installed successfully" "$GREEN"
    else
      print_msg "Skipping Mosquitto installation" "$YELLOW"
      return 0
    fi
  else
    print_msg "Mosquitto is already installed" "$GREEN"
  fi

  # Configure Mosquitto for WebSockets - make this more prominent
  print_msg "=============================================" "$BLUE"
  print_msg "MQTT WebSockets Configuration" "$BLUE"
  print_msg "This enables browser-based MQTT clients to connect" "$BLUE"
  print_msg "=============================================" "$BLUE"

  if ask_yn "Would you like to configure Mosquitto for WebSockets support?" true; then
    print_msg "Configuring Mosquitto for WebSockets..." "$BLUE"

    local config_file=""
    local passwd_file=""

    if [[ $OS == linux ]]; then
      config_file="/etc/mosquitto/conf.d/default.conf"
      passwd_file="/etc/mosquitto/passwd"

      # Create necessary directories if they don't exist
      if [[ ! -d "/etc/mosquitto/conf.d" ]]; then
        require_root
        mkdir -p "/etc/mosquitto/conf.d"
        print_msg "Created directory: /etc/mosquitto/conf.d" "$GREEN"
      fi

      # Ensure the directory for the password file exists
      if [[ ! -d "/etc/mosquitto" ]]; then
        require_root
        mkdir -p "/etc/mosquitto"
        print_msg "Created directory: /etc/mosquitto" "$GREEN"
      fi

      # Check if Mosquitto is properly installed
      if [[ ! -f "/etc/mosquitto/mosquitto.conf" ]]; then
        print_msg "Warning: Main Mosquitto config file not found" "$YELLOW"
        print_msg "Creating a basic mosquitto.conf file..." "$BLUE"
        require_root
        echo "# Basic Mosquitto configuration created by mqtt-monitor installer" > "/etc/mosquitto/mosquitto.conf"
        echo "include_dir /etc/mosquitto/conf.d" >> "/etc/mosquitto/mosquitto.conf"
        print_msg "Created basic mosquitto.conf file" "$GREEN"
      fi

      # Create or update config file
      require_root
      cat > "$config_file" << EOF
# MQTT Device Monitor configuration
# Configured by manage.sh script

# Standard MQTT listener
listener 1883
protocol mqtt

# WebSockets listener
listener 9001
protocol websockets

# Security settings
allow_anonymous false
password_file $passwd_file
EOF

      # Create password file if it doesn't exist
      if [[ ! -f "$passwd_file" ]]; then
        print_msg "Creating Mosquitto password file..." "$BLUE"

        # Ensure the directory exists with proper permissions
        require_root
        mkdir -p "$(dirname "$passwd_file")"
        # Set proper directory permissions
        require_root
        chown -R mosquitto:mosquitto "$(dirname "$passwd_file")" 2>/dev/null || true
        chmod 755 "$(dirname "$passwd_file")" 2>/dev/null || true
        print_msg "Verified directory for password file: $(dirname "$passwd_file")" "$GREEN"

        # Prompt for username (can be empty)
        echo -n "Enter username for Mosquitto authentication (leave empty for anonymous access): "
        read -r mqtt_user </dev/tty

        # Store for later use in .env
        MQTT_USERNAME="$mqtt_user"
        MQTT_PASSWORD=""

        # Only create password file if username is provided
        if [[ -n "$mqtt_user" ]]; then
          # Create password file with error handling
          require_root
          print_msg "Creating password file at $passwd_file..." "$BLUE"

          # Ensure the directory exists
          require_root mkdir -p "$(dirname "$passwd_file")" || true

          # Check if mosquitto_passwd command is available
          if ! command_exists mosquitto_passwd; then
            print_msg "mosquitto_passwd command not found. Installing mosquitto-clients..." "$YELLOW"
            if [[ $DISTRO == "ubuntu" || $DISTRO == "debian" ]]; then
              require_root apt-get update -y
              require_root apt-get install -y mosquitto-clients
            elif [[ $DISTRO == "arch" ]]; then
              require_root pacman -Sy --noconfirm mosquitto
            else
              print_msg "Could not install mosquitto-clients automatically." "$RED"
              print_msg "Please install mosquitto-clients manually and try again." "$RED"
              return 1
            fi
          fi

          # Ensure the directory has proper permissions
          print_msg "Setting proper directory permissions..." "$BLUE"
          require_root mkdir -p "$(dirname "$passwd_file")" || true
          require_root chown -R mosquitto:mosquitto "$(dirname "$passwd_file")" 2>/dev/null || true
          require_root chmod -R 755 "$(dirname "$passwd_file")" 2>/dev/null || true

          # Create the password file using mosquitto_passwd
          # This will prompt the user for a password twice
          print_msg "You will be prompted to enter a password for user '$mqtt_user'" "$YELLOW"
          print_msg "Please enter the same password twice when prompted" "$YELLOW"

          # Try up to 3 times to create the password file
          local max_attempts=3
          local attempt=1
          local success=false

          while [[ $attempt -le $max_attempts && $success == false ]]; do
            print_msg "Attempt $attempt of $max_attempts to create password file..." "$BLUE"

            # Try to create the password file
            require_root mosquitto_passwd -c "$passwd_file" "$mqtt_user"

            # Check if the password file was created successfully
            if [[ -f "$passwd_file" && -s "$passwd_file" ]]; then
              success=true
              print_msg "Password file created successfully!" "$GREEN"
            else
              attempt=$((attempt + 1))
              if [[ $attempt -le $max_attempts ]]; then
                print_msg "Failed to create password file. Trying again..." "$YELLOW"
                sleep 1
              fi
            fi
          done

          # If all attempts failed, try a different approach
          if [[ $success == false ]]; then
            print_msg "All attempts to create password file failed. Trying alternative method..." "$RED"

            # Try to create a temporary password file and then copy it
            local temp_passwd=$(mktemp)
            print_msg "Creating temporary password file at $temp_passwd" "$BLUE"
            print_msg "You will be prompted to enter a password for user '$mqtt_user'" "$YELLOW"
            print_msg "Please enter the same password twice when prompted" "$YELLOW"

            # Create password in temporary file
            mosquitto_passwd -c "$temp_passwd" "$mqtt_user"

            # Check if the temporary file was created successfully
            if [[ -f "$temp_passwd" && -s "$temp_passwd" ]]; then
              print_msg "Temporary password file created successfully. Copying to $passwd_file" "$GREEN"
              require_root cp "$temp_passwd" "$passwd_file"
              rm -f "$temp_passwd"

              # Check if the copy was successful
              if [[ -f "$passwd_file" && -s "$passwd_file" ]]; then
                success=true
                print_msg "Password file copied successfully!" "$GREEN"
              fi
            else
              print_msg "Failed to create temporary password file." "$RED"
              rm -f "$temp_passwd"
            fi
          fi

          # If still not successful, create the file manually
          if [[ $success == false ]]; then
            print_msg "All methods failed. Creating password file manually..." "$RED"
            print_msg "Enter password for user '$mqtt_user': " "$YELLOW"
            read -rs manual_pass </dev/tty
            echo  # Add newline after password input

            if [[ -n "$manual_pass" ]]; then
              # Create the password file manually
              require_root touch "$passwd_file"
              echo "$mqtt_user:$(echo -n "$manual_pass" | openssl passwd -6 -stdin)" | require_root tee "$passwd_file" > /dev/null

              # Check if the file was created successfully
              if [[ -f "$passwd_file" && -s "$passwd_file" ]]; then
                success=true
                print_msg "Password file created manually!" "$GREEN"
              fi
            fi
          fi

          # Final check
          if [[ $success == false ]]; then
            print_msg "All attempts to create password file failed." "$RED"
            print_msg "Please check your system configuration and try again." "$RED"
            return 1
          fi

          print_msg "Password file created successfully at $passwd_file" "$GREEN"

          # Set proper ownership and permissions
          print_msg "Setting proper ownership and permissions..." "$BLUE"
          require_root chown mosquitto:mosquitto "$passwd_file" 2>/dev/null || true
          require_root chmod 600 "$passwd_file" 2>/dev/null || true

          # Verify the file exists and has content
          if [[ -s "$passwd_file" ]]; then
            print_msg "Password file created successfully at $passwd_file" "$GREEN"
            # Show file info but not content (for security)
            require_root ls -la "$passwd_file"
          else
            print_msg "Warning: Password file may not have been created properly" "$RED"
            print_msg "Authentication may not work correctly" "$RED"
          fi

          # Update config file with the correct password file path
          if [[ "$passwd_file" != "/etc/mosquitto/passwd" ]]; then
            print_msg "Updating config to use password file at $passwd_file" "$YELLOW"
            local config_content
            config_content=$(cat "$config_file")
            config_content=${config_content/password_file \/etc\/mosquitto\/passwd/password_file $passwd_file}
            echo "$config_content" | require_root tee "$config_file" > /dev/null
          fi

          # Update config to require authentication
          print_msg "Configuring Mosquitto to require authentication..." "$GREEN"
        else
          # No authentication - update config to allow anonymous access
          print_msg "Configuring Mosquitto for anonymous access..." "$YELLOW"

          # Update the config file to allow anonymous access
          local config_content
          config_content=$(cat "$config_file")
          config_content=${config_content/allow_anonymous false/allow_anonymous true}
          config_content=${config_content/password_file $passwd_file/# No password file - anonymous access}

          # Write updated config
          require_root
          echo "$config_content" | require_root tee "$config_file" > /dev/null
        fi
      else
        print_msg "Password file already exists at $passwd_file" "$GREEN"

        if ask_yn "Would you like to add a new user?" false; then
          echo -n "Enter username for Mosquitto authentication (leave empty to cancel): "
          read -r mqtt_user </dev/tty

          # Only proceed if username is provided
          if [[ -n "$mqtt_user" ]]; then
            # Store username for later use in .env
            MQTT_USERNAME="$mqtt_user"

            # Verify the password file exists
            if [[ ! -f "$passwd_file" ]]; then
              print_msg "Password file not found. Creating it..." "$YELLOW"
              require_root touch "$passwd_file" || {
                print_msg "Cannot create password file. Using alternative location..." "$RED"
                passwd_file="/tmp/mosquitto_passwd"
                require_root touch "$passwd_file"

                # Update config file with the new password file path
                local config_content
                config_content=$(cat "$config_file")
                config_content=${config_content/password_file \/etc\/mosquitto\/passwd/password_file $passwd_file}
                echo "$config_content" | require_root tee "$config_file" > /dev/null
              }
            fi

            # Check if mosquitto_passwd command is available
            if ! command_exists mosquitto_passwd; then
              print_msg "mosquitto_passwd command not found. Installing mosquitto-clients..." "$YELLOW"
              if [[ $DISTRO == "ubuntu" || $DISTRO == "debian" ]]; then
                require_root apt-get update -y
                require_root apt-get install -y mosquitto-clients
              elif [[ $DISTRO == "arch" ]]; then
                require_root pacman -Sy --noconfirm mosquitto
              else
                print_msg "Could not install mosquitto-clients automatically." "$RED"
                print_msg "Please install mosquitto-clients manually and try again." "$RED"
                return 1
              fi
            fi

            # Add user with mosquitto_passwd
            print_msg "Adding user to password file: $passwd_file" "$BLUE"
            print_msg "You will be prompted to enter a password for user '$mqtt_user'" "$YELLOW"
            print_msg "Please enter the same password twice when prompted" "$YELLOW"

            # Try up to 3 times to add the user
            local max_attempts=3
            local attempt=1
            local success=false

            while [[ $attempt -le $max_attempts && $success == false ]]; do
              print_msg "Attempt $attempt of $max_attempts to add user..." "$BLUE"

              # Try to add the user
              require_root mosquitto_passwd "$passwd_file" "$mqtt_user"

              # Verify the user was added
              if grep -q "$mqtt_user:" "$passwd_file" 2>/dev/null; then
                success=true
                print_msg "User added successfully!" "$GREEN"
              else
                attempt=$((attempt + 1))
                if [[ $attempt -le $max_attempts ]]; then
                  print_msg "Failed to add user. Trying again..." "$YELLOW"
                  sleep 1
                fi
              fi
            done

            # If all attempts failed, try a different approach
            if [[ $success == false ]]; then
              print_msg "All attempts to add user failed. Trying alternative method..." "$RED"

              # Try to create a temporary password file and then merge it
              local temp_passwd=$(mktemp)
              print_msg "Creating temporary password file at $temp_passwd" "$BLUE"
              print_msg "You will be prompted to enter a password for user '$mqtt_user'" "$YELLOW"
              print_msg "Please enter the same password twice when prompted" "$YELLOW"

              # Create password in temporary file
              mosquitto_passwd -c "$temp_passwd" "$mqtt_user"

              # Check if the temporary file was created successfully
              if [[ -f "$temp_passwd" && -s "$temp_passwd" ]]; then
                print_msg "Temporary password file created successfully. Merging with $passwd_file" "$GREEN"

                # Extract the user line from the temporary file
                local user_line=$(grep "^$mqtt_user:" "$temp_passwd")

                if [[ -n "$user_line" ]]; then
                  # Remove any existing entry for this user
                  require_root sed -i "/^$mqtt_user:/d" "$passwd_file" 2>/dev/null || true

                  # Append the new user line
                  echo "$user_line" | require_root tee -a "$passwd_file" > /dev/null

                  # Verify the user was added
                  if grep -q "$mqtt_user:" "$passwd_file" 2>/dev/null; then
                    success=true
                    print_msg "User added successfully via merge!" "$GREEN"
                  fi
                fi

                # Clean up
                rm -f "$temp_passwd"
              else
                print_msg "Failed to create temporary password file." "$RED"
                rm -f "$temp_passwd"
              fi
            fi

            # If still not successful, add the user manually
            if [[ $success == false ]]; then
              print_msg "All methods failed. Adding user manually..." "$RED"
              print_msg "Enter password for user '$mqtt_user': " "$YELLOW"
              read -rs manual_pass </dev/tty
              echo  # Add newline after password input

              if [[ -n "$manual_pass" ]]; then
                # Remove any existing entry for this user
                require_root sed -i "/^$mqtt_user:/d" "$passwd_file" 2>/dev/null || true

                # Add the user manually
                echo "$mqtt_user:$(echo -n "$manual_pass" | openssl passwd -6 -stdin)" | require_root tee -a "$passwd_file" > /dev/null

                # Verify the user was added
                if grep -q "$mqtt_user:" "$passwd_file" 2>/dev/null; then
                  success=true
                  print_msg "User added manually!" "$GREEN"
                fi
              fi
            fi

            # Final check
            if [[ $success == false ]]; then
              print_msg "All attempts to add user failed." "$RED"
              print_msg "Please check your system configuration and try again." "$RED"
              return 1
            fi

            # Verify the user was added
            if grep -q "$mqtt_user:" "$passwd_file" 2>/dev/null; then
              print_msg "User $mqtt_user added successfully to $passwd_file" "$GREEN"

              # Set proper permissions
              require_root chown mosquitto:mosquitto "$passwd_file" 2>/dev/null || true
              require_root chmod 600 "$passwd_file" 2>/dev/null || true

              # Restart Mosquitto to apply changes
              print_msg "Restarting Mosquitto service to apply changes..." "$BLUE"
              if systemctl is-active --quiet mosquitto; then
                require_root systemctl restart mosquitto
                print_msg "Mosquitto service restarted" "$GREEN"
              else
                print_msg "Mosquitto service not running, skipping restart" "$YELLOW"
              fi
            else
              print_msg "Warning: Failed to verify user was added" "$RED"
            fi
          else
            print_msg "No username provided, skipping user addition" "$YELLOW"
          fi
        fi
      fi

      # Restart Mosquitto service
      print_msg "Restarting Mosquitto service..." "$BLUE"
      require_root
      systemctl restart mosquitto

      # Enable Mosquitto service to start at boot
      print_msg "Enabling Mosquitto service to start at boot..." "$BLUE"
      require_root
      systemctl enable mosquitto

      # Display configuration summary
      print_msg "=============================================" "$GREEN"
      print_msg "Mosquitto Configuration Summary (Linux)" "$GREEN"
      print_msg "Config file: $config_file" "$GREEN"
      print_msg "Password file: $passwd_file" "$GREEN"
      print_msg "MQTT port: 1883" "$GREEN"
      print_msg "WebSockets port: 9001" "$GREEN"
      print_msg "=============================================" "$GREEN"

    else
      # macOS configuration
      config_file="$(brew --prefix)/etc/mosquitto/mosquitto.conf"
      passwd_file="$(brew --prefix)/etc/mosquitto/passwd"

      # Create or update config file
      cat > "$config_file" << EOF
# MQTT Device Monitor configuration
# Configured by manage.sh script

# Standard MQTT listener
listener 1883
protocol mqtt

# WebSockets listener
listener 9001
protocol websockets

# Security settings
allow_anonymous false
password_file $passwd_file
EOF

      # Create password file if it doesn't exist
      if [[ ! -f "$passwd_file" ]]; then
        print_msg "Creating Mosquitto password file..." "$BLUE"

        # Ensure the directory exists with proper permissions
        mkdir -p "$(dirname "$passwd_file")"
        # Set proper directory permissions
        chmod 755 "$(dirname "$passwd_file")" 2>/dev/null || true
        print_msg "Verified directory for password file: $(dirname "$passwd_file")" "$GREEN"

        # Prompt for username (can be empty)
        echo -n "Enter username for Mosquitto authentication (leave empty for anonymous access): "
        read -r mqtt_user </dev/tty

        # Store for later use in .env
        MQTT_USERNAME="$mqtt_user"
        MQTT_PASSWORD=""

        # Only create password file if username is provided
        if [[ -n "$mqtt_user" ]]; then
          # Create password file with error handling
          print_msg "Creating password file at $passwd_file..." "$BLUE"

          # Ensure the directory exists
          mkdir -p "$(dirname "$passwd_file")" || true

          # Check if mosquitto_passwd command is available
          if ! command_exists mosquitto_passwd; then
            print_msg "mosquitto_passwd command not found. Installing mosquitto..." "$YELLOW"
            if command_exists brew; then
              brew install mosquitto
            else
              print_msg "Homebrew not found. Please install mosquitto manually and try again." "$RED"
              return 1
            fi
          fi

          # Ensure the directory has proper permissions
          print_msg "Setting proper directory permissions..." "$BLUE"
          mkdir -p "$(dirname "$passwd_file")" || true
          chmod -R 755 "$(dirname "$passwd_file")" 2>/dev/null || true

          # Create the password file using mosquitto_passwd
          # This will prompt the user for a password twice
          print_msg "You will be prompted to enter a password for user '$mqtt_user'" "$YELLOW"
          print_msg "Please enter the same password twice when prompted" "$YELLOW"

          # Try up to 3 times to create the password file
          local max_attempts=3
          local attempt=1
          local success=false

          while [[ $attempt -le $max_attempts && $success == false ]]; do
            print_msg "Attempt $attempt of $max_attempts to create password file..." "$BLUE"

            # Try to create the password file
            mosquitto_passwd -c "$passwd_file" "$mqtt_user"

            # Check if the password file was created successfully
            if [[ -f "$passwd_file" && -s "$passwd_file" ]]; then
              success=true
              print_msg "Password file created successfully!" "$GREEN"
            else
              attempt=$((attempt + 1))
              if [[ $attempt -le $max_attempts ]]; then
                print_msg "Failed to create password file. Trying again..." "$YELLOW"
                sleep 1
              fi
            fi
          done

          # If all attempts failed, try a different approach
          if [[ $success == false ]]; then
            print_msg "All attempts to create password file failed. Trying alternative method..." "$RED"

            # Try to create a temporary password file and then copy it
            local temp_passwd=$(mktemp)
            print_msg "Creating temporary password file at $temp_passwd" "$BLUE"
            print_msg "You will be prompted to enter a password for user '$mqtt_user'" "$YELLOW"
            print_msg "Please enter the same password twice when prompted" "$YELLOW"

            # Create password in temporary file
            mosquitto_passwd -c "$temp_passwd" "$mqtt_user"

            # Check if the temporary file was created successfully
            if [[ -f "$temp_passwd" && -s "$temp_passwd" ]]; then
              print_msg "Temporary password file created successfully. Copying to $passwd_file" "$GREEN"
              cp "$temp_passwd" "$passwd_file"
              rm -f "$temp_passwd"

              # Check if the copy was successful
              if [[ -f "$passwd_file" && -s "$passwd_file" ]]; then
                success=true
                print_msg "Password file copied successfully!" "$GREEN"
              fi
            else
              print_msg "Failed to create temporary password file." "$RED"
              rm -f "$temp_passwd"
            fi
          fi

          # If still not successful, create the file manually
          if [[ $success == false ]]; then
            print_msg "All methods failed. Creating password file manually..." "$RED"
            print_msg "Enter password for user '$mqtt_user': " "$YELLOW"
            read -rs manual_pass </dev/tty
            echo  # Add newline after password input

            if [[ -n "$manual_pass" ]]; then
              # Create the password file manually
              touch "$passwd_file"
              echo "$mqtt_user:$(echo -n "$manual_pass" | openssl passwd -6 -stdin)" > "$passwd_file"

              # Check if the file was created successfully
              if [[ -f "$passwd_file" && -s "$passwd_file" ]]; then
                success=true
                print_msg "Password file created manually!" "$GREEN"
              fi
            fi
          fi

          # Final check
          if [[ $success == false ]]; then
            print_msg "All attempts to create password file failed." "$RED"
            print_msg "Please check your system configuration and try again." "$RED"
            return 1
          fi

          print_msg "Password file created successfully at $passwd_file" "$GREEN"

          # Set proper permissions
          print_msg "Setting proper permissions..." "$BLUE"
          chmod 600 "$passwd_file" 2>/dev/null || true

          # Verify the file exists and has content
          if [[ -s "$passwd_file" ]]; then
            print_msg "Password file created successfully at $passwd_file" "$GREEN"
            # Show file info but not content (for security)
            ls -la "$passwd_file"
          else
            print_msg "Warning: Password file may not have been created properly" "$RED"
            print_msg "Authentication may not work correctly" "$RED"
          fi

          # Update config file with the correct password file path
          if [[ "$passwd_file" != "$(brew --prefix)/etc/mosquitto/passwd" ]]; then
            print_msg "Updating config to use password file at $passwd_file" "$YELLOW"
            local config_content
            config_content=$(cat "$config_file")
            config_content=${config_content/password_file $(brew --prefix)\/etc\/mosquitto\/passwd/password_file $passwd_file}
            echo "$config_content" > "$config_file"
          fi

          # Update config to require authentication
          print_msg "Configuring Mosquitto to require authentication..." "$GREEN"
        else
          # No authentication - update config to allow anonymous access
          print_msg "Configuring Mosquitto for anonymous access..." "$YELLOW"

          # Update the config file to allow anonymous access
          local config_content
          config_content=$(cat "$config_file")
          config_content=${config_content/allow_anonymous false/allow_anonymous true}
          config_content=${config_content/password_file $passwd_file/# No password file - anonymous access}

          # Write updated config
          echo "$config_content" > "$config_file"
        fi
      else
        print_msg "Password file already exists at $passwd_file" "$GREEN"

        if ask_yn "Would you like to add a new user?" false; then
          echo -n "Enter username for Mosquitto authentication (leave empty to cancel): "
          read -r mqtt_user </dev/tty

          # Only proceed if username is provided
          if [[ -n "$mqtt_user" ]]; then
            # Prompt for password with validation
            local mqtt_pass=""
            while [[ -z "$mqtt_pass" ]]; do
              echo -n "Enter password for $mqtt_user: "
              read -rs mqtt_pass </dev/tty
              echo  # Add newline after password input

              if [[ -z "$mqtt_pass" ]]; then
                print_msg "Password cannot be empty when username is provided. Please try again." "$RED"
              fi
            done

            # Store for later use in .env
            MQTT_USERNAME="$mqtt_user"
            MQTT_PASSWORD="$mqtt_pass"

            # Verify the password file exists
            if [[ ! -f "$passwd_file" ]]; then
              print_msg "Password file not found. Creating it..." "$YELLOW"
              touch "$passwd_file" || {
                print_msg "Cannot create password file. Using alternative location..." "$RED"
                passwd_file="/tmp/mosquitto_passwd"
                touch "$passwd_file"

                # Update config file with the new password file path
                local config_content
                config_content=$(cat "$config_file")
                config_content=${config_content/password_file $(brew --prefix)\/etc\/mosquitto\/passwd/password_file $passwd_file}
                echo "$config_content" > "$config_file"
              }
            fi

            # Check if mosquitto_passwd command is available
            if ! command_exists mosquitto_passwd; then
              print_msg "mosquitto_passwd command not found. Installing mosquitto..." "$YELLOW"
              if command_exists brew; then
                brew install mosquitto
              else
                print_msg "Homebrew not found. Please install mosquitto manually and try again." "$RED"
                return 1
              fi
            fi

            # Add user with mosquitto_passwd
            print_msg "Adding user to password file: $passwd_file" "$BLUE"
            print_msg "You will be prompted to enter a password for user '$mqtt_user'" "$YELLOW"
            print_msg "Please enter the same password twice when prompted" "$YELLOW"

            # Try up to 3 times to add the user
            local max_attempts=3
            local attempt=1
            local success=false

            while [[ $attempt -le $max_attempts && $success == false ]]; do
              print_msg "Attempt $attempt of $max_attempts to add user..." "$BLUE"

              # Try to add the user
              mosquitto_passwd "$passwd_file" "$mqtt_user"

              # Verify the user was added
              if grep -q "$mqtt_user:" "$passwd_file" 2>/dev/null; then
                success=true
                print_msg "User added successfully!" "$GREEN"
              else
                attempt=$((attempt + 1))
                if [[ $attempt -le $max_attempts ]]; then
                  print_msg "Failed to add user. Trying again..." "$YELLOW"
                  sleep 1
                fi
              fi
            done

            # If all attempts failed, try a different approach
            if [[ $success == false ]]; then
              print_msg "All attempts to add user failed. Trying alternative method..." "$RED"

              # Try to create a temporary password file and then merge it
              local temp_passwd=$(mktemp)
              print_msg "Creating temporary password file at $temp_passwd" "$BLUE"
              print_msg "You will be prompted to enter a password for user '$mqtt_user'" "$YELLOW"
              print_msg "Please enter the same password twice when prompted" "$YELLOW"

              # Create password in temporary file
              mosquitto_passwd -c "$temp_passwd" "$mqtt_user"

              # Check if the temporary file was created successfully
              if [[ -f "$temp_passwd" && -s "$temp_passwd" ]]; then
                print_msg "Temporary password file created successfully. Merging with $passwd_file" "$GREEN"

                # Extract the user line from the temporary file
                local user_line=$(grep "^$mqtt_user:" "$temp_passwd")

                if [[ -n "$user_line" ]]; then
                  # Remove any existing entry for this user
                  sed -i.bak "/^$mqtt_user:/d" "$passwd_file" 2>/dev/null || true

                  # Append the new user line
                  echo "$user_line" >> "$passwd_file"

                  # Verify the user was added
                  if grep -q "$mqtt_user:" "$passwd_file" 2>/dev/null; then
                    success=true
                    print_msg "User added successfully via merge!" "$GREEN"
                  fi

                  # Clean up backup file
                  rm -f "${passwd_file}.bak" 2>/dev/null || true
                fi

                # Clean up
                rm -f "$temp_passwd"
              else
                print_msg "Failed to create temporary password file." "$RED"
                rm -f "$temp_passwd"
              fi
            fi

            # If still not successful, add the user manually
            if [[ $success == false ]]; then
              print_msg "All methods failed. Adding user manually..." "$RED"
              print_msg "Enter password for user '$mqtt_user': " "$YELLOW"
              read -rs manual_pass </dev/tty
              echo  # Add newline after password input

              if [[ -n "$manual_pass" ]]; then
                # Remove any existing entry for this user
                sed -i.bak "/^$mqtt_user:/d" "$passwd_file" 2>/dev/null || true
                rm -f "${passwd_file}.bak" 2>/dev/null || true

                # Add the user manually
                echo "$mqtt_user:$(echo -n "$manual_pass" | openssl passwd -6 -stdin)" >> "$passwd_file"

                # Verify the user was added
                if grep -q "$mqtt_user:" "$passwd_file" 2>/dev/null; then
                  success=true
                  print_msg "User added manually!" "$GREEN"
                fi
              fi
            fi

            # Final check
            if [[ $success == false ]]; then
              print_msg "All attempts to add user failed." "$RED"
              print_msg "Please check your system configuration and try again." "$RED"
              return 1
            fi

            # Set proper permissions
            chmod 600 "$passwd_file" 2>/dev/null || true

            # Verify the user was added
            if grep -q "$mqtt_user:" "$passwd_file" 2>/dev/null; then
              print_msg "User $mqtt_user added successfully to $passwd_file" "$GREEN"
            else
              print_msg "Warning: Failed to verify user was added" "$RED"
            fi
          else
            print_msg "No username provided, skipping user addition" "$YELLOW"
          fi
        fi
      fi

      # Restart Mosquitto service
      print_msg "Restarting Mosquitto service..." "$BLUE"
      brew services restart mosquitto

      # Display configuration summary
      print_msg "=============================================" "$GREEN"
      print_msg "Mosquitto Configuration Summary (macOS)" "$GREEN"
      print_msg "Config file: $config_file" "$GREEN"
      print_msg "Password file: $passwd_file" "$GREEN"
      print_msg "MQTT port: 1883" "$GREEN"
      print_msg "WebSockets port: 9001" "$GREEN"
      print_msg "=============================================" "$GREEN"
    fi

    print_msg "Mosquitto configured successfully for WebSockets" "$GREEN"
    print_msg "MQTT broker is now available on port 1883 (MQTT) and 9001 (WebSockets)" "$GREEN"
    print_msg "Remember to use the configured username and password in your .env file" "$YELLOW"

    # Add note about firewall configuration
    print_msg "NOTE: Make sure ports 1883 and 9001 are open in your firewall" "$YELLOW"
    print_msg "for remote clients to connect to your MQTT broker" "$YELLOW"
  else
    print_msg "Skipping Mosquitto WebSockets configuration" "$YELLOW"
  fi

  return 0
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

  # Create a temporary directory for cloning
  local TEMP_DIR=$(mktemp -d)
  print_msg "Created temporary directory: $TEMP_DIR" "$BLUE"

  # Clone the repository to the temporary directory
  print_msg "Cloning repository to temporary directory..." "$BLUE"
  if ! git clone --depth 1 "$REPO_URL" "$TEMP_DIR"; then
    print_msg "Git clone failed" "$RED"
    rm -rf "$TEMP_DIR"
    return 1
  fi

  # Copy the mqtt-monitor directory to the installation directory
  print_msg "Copying mqtt-monitor files to installation directory..." "$BLUE"
  if ! cp -R "$TEMP_DIR/mqtt-monitor/"* "$INSTALL_DIR/"; then
    print_msg "Failed to copy mqtt-monitor files" "$RED"
    rm -rf "$TEMP_DIR"
    return 1
  fi

  # Clean up the temporary directory
  print_msg "Cleaning up temporary directory..." "$BLUE"
  rm -rf "$TEMP_DIR"

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

  # ─── Install uv if needed ───────────────────────────────────────────────────
  local UV_COMMAND=""

  # First check if uv is already available
  if command_exists uv; then
    print_msg "uv found in PATH" "$GREEN"
    UV_COMMAND="uv"
  else
    print_msg "uv not found – installing..." "$YELLOW"

    # macOS-specific installation via Homebrew if available
    if [[ $OS == "macos" ]] && command_exists brew; then
      print_msg "Installing uv via Homebrew on macOS" "$BLUE"
      brew install uv || true

      if command_exists uv; then
        print_msg "uv installed successfully via Homebrew" "$GREEN"
        UV_COMMAND="uv"
      fi
    fi

    # If still not available, try pipx
    if [[ -z "$UV_COMMAND" ]]; then
      print_msg "Installing uv via pipx" "$BLUE"

      # Install pipx if needed
      if ! command_exists pipx; then
        print_msg "pipx not found – installing" "$YELLOW"
        "$PYTHON" -m pip install --user --upgrade pipx
        "$PYTHON" -m pipx ensurepath
        export PATH="$HOME/.local/bin:$PATH"
      fi

      # Try to install uv with pipx
      if command_exists pipx; then
        pipx install --force uv || true

        if command_exists uv; then
          print_msg "uv installed successfully via pipx" "$GREEN"
          UV_COMMAND="uv"
        fi
      fi
    fi

    # Last resort: direct pip installation
    if [[ -z "$UV_COMMAND" ]]; then
      print_msg "Installing uv via pip" "$BLUE"
      "$PYTHON" -m pip install --user --upgrade uv

      # Update PATH to include user bin directories
      export PATH="$HOME/.local/bin:$PATH"

      if command_exists uv; then
        print_msg "uv installed successfully via pip" "$GREEN"
        UV_COMMAND="uv"
      else
        # Try to find uv binary
        print_msg "Searching for uv binary..." "$YELLOW"
        local UV_PATH=""

        # Common locations based on OS
        if [[ $OS == "macos" ]]; then
          UV_PATH=$(find "$HOME/.local/bin" "/usr/local/bin" "/opt/homebrew/bin" -name uv -type f 2>/dev/null | head -1)
        else
          UV_PATH=$(find "$HOME/.local/bin" "/usr/local/bin" -name uv -type f 2>/dev/null | head -1)
        fi

        if [[ -n "$UV_PATH" ]]; then
          print_msg "Found uv at $UV_PATH" "$GREEN"
          UV_COMMAND="$UV_PATH"
          export PATH="$(dirname "$UV_PATH"):$PATH"
        fi
      fi
    fi
  fi

  # ─── Create virtual environment ───────────────────────────────────────────────
  if [[ -n "$UV_COMMAND" ]]; then
    print_msg "Creating virtual environment with uv" "$BLUE"

    # Remove existing venv if it exists but is broken
    if [[ -d ".venv" && ! -x ".venv/bin/python3" && ! -x ".venv/bin/python" ]]; then
      print_msg "Existing virtual environment appears broken, removing it" "$YELLOW"
      rm -rf .venv
    fi

    # Create virtual environment with uv
    run_as_user "$UV_COMMAND" venv .venv

    # Verify the virtual environment was created successfully
    if [[ ! -d ".venv" ]]; then
      print_msg "Failed to create virtual environment with uv" "$RED"
      print_msg "Falling back to standard venv" "$YELLOW"
      run_as_user "$PYTHON" -m venv .venv
    else
      print_msg "Virtual environment created successfully with uv" "$GREEN"
    fi
  else
    print_msg "uv not available - using standard venv" "$YELLOW"

    # Try pyenv if available
    if command_exists pyenv; then
      print_msg "Using pyenv to create virtual environment" "$BLUE"
      run_as_user pyenv virtualenv 3.10 mqtt-monitor-env || true
      run_as_user ln -sf "$(pyenv prefix mqtt-monitor-env)" .venv
    else
      # Fallback to standard venv
      print_msg "Using standard venv module" "$BLUE"
      run_as_user "$PYTHON" -m venv .venv
    fi
  fi

  # ─── Verify Python environment ───────────────────────────────────────────────
  # Find Python in the virtual environment
  local VENV_PYTHON=""

  if [[ -x ".venv/bin/python3" ]]; then
    VENV_PYTHON=".venv/bin/python3"
  elif [[ -x ".venv/bin/python" ]]; then
    VENV_PYTHON=".venv/bin/python"
  fi

  # If no Python found, try to fix the virtual environment
  if [[ -z "$VENV_PYTHON" ]]; then
    print_msg "No Python executable found in virtual environment" "$RED"
    print_msg "Attempting to recreate virtual environment" "$YELLOW"

    # Remove broken venv
    rm -rf .venv

    # Create new venv with standard module
    run_as_user "$PYTHON" -m venv .venv

    # Check again
    if [[ -x ".venv/bin/python3" ]]; then
      VENV_PYTHON=".venv/bin/python3"
    elif [[ -x ".venv/bin/python" ]]; then
      VENV_PYTHON=".venv/bin/python"
    else
      print_msg "Failed to create a working virtual environment" "$RED"
      return 1
    fi
  fi

  print_msg "Using Python at $VENV_PYTHON" "$GREEN"

  # ─── Install requirements ───────────────────────────────────────────────────
  if [[ -f "requirements.txt" ]]; then
    print_msg "Installing Python requirements..." "$BLUE"

    if [[ -n "$UV_COMMAND" ]]; then
      # Use uv for faster package installation
      print_msg "Using uv for package installation (faster)" "$GREEN"

      # macOS-specific handling
      if [[ $OS == "macos" ]]; then
        print_msg "Using macOS-specific installation with uv" "$BLUE"

        # First try with uv directly
        run_as_user "$UV_COMMAND" pip install -r requirements.txt || {
          print_msg "Direct uv installation had issues, trying with venv activation" "$YELLOW"

          # Try with explicit venv path
          run_as_user "$UV_COMMAND" pip install --python "$VENV_PYTHON" -r requirements.txt || {
            print_msg "uv installation failed, falling back to pip" "$RED"
            run_as_user "$VENV_PYTHON" -m pip install -r requirements.txt
          }
        }
      else
        # Standard installation for other platforms
        run_as_user "$UV_COMMAND" pip install -r requirements.txt || {
          print_msg "uv installation failed, falling back to pip" "$RED"
          run_as_user "$VENV_PYTHON" -m pip install -r requirements.txt
        }
      fi
    else
      # Fall back to regular pip
      print_msg "Using standard pip for package installation" "$YELLOW"
      run_as_user "$VENV_PYTHON" -m pip install -r requirements.txt
    fi

    print_msg "Python requirements installed" "$GREEN"

    # Verify critical packages are installed
    print_msg "Verifying critical packages..." "$BLUE"
    if ! run_as_user "$VENV_PYTHON" -c "import dotenv" &>/dev/null; then
      print_msg "python-dotenv package not found, installing directly" "$YELLOW"
      run_as_user "$VENV_PYTHON" -m pip install python-dotenv
    fi

    if ! run_as_user "$VENV_PYTHON" -c "import flask" &>/dev/null; then
      print_msg "Flask package not found, installing directly" "$YELLOW"
      run_as_user "$VENV_PYTHON" -m pip install flask
    fi

    print_msg "Critical packages verified" "$GREEN"
  fi

  print_msg "Virtual environment setup complete" "$GREEN"
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
  local mqtt_user="${MQTT_USERNAME:-}"  # Use value from Mosquitto config if available
  local mqtt_pass="${MQTT_PASSWORD:-}"  # Use value from Mosquitto config if available
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
  if [[ -n "$mqtt_user" && -n "$mqtt_pass" ]]; then
    print_msg "Using MQTT credentials from Mosquitto configuration" "$GREEN"
    print_msg "Username: $mqtt_user" "$GREEN"
    print_msg "Password: [hidden]" "$GREEN"

    if ask_yn "Would you like to change these credentials?" false; then
      mqtt_user=""
      mqtt_pass=""
    fi
  fi

  # Only prompt for credentials if not already set
  if [[ -z "$mqtt_user" ]]; then
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

    # Find the correct Python executable in the virtual environment
    local VENV_PYTHON=""
    if [[ -x "$INSTALL_DIR/.venv/bin/python3" ]]; then
      VENV_PYTHON="$INSTALL_DIR/.venv/bin/python3"
    elif [[ -x "$INSTALL_DIR/.venv/bin/python" ]]; then
      VENV_PYTHON="$INSTALL_DIR/.venv/bin/python"
    else
      print_msg "No Python executable found in virtual environment" "$RED"
      print_msg "Attempting to fix virtual environment..." "$YELLOW"

      # Try to recreate the virtual environment
      cd "$INSTALL_DIR" || return 1
      if command_exists uv; then
        run_as_user uv venv .venv
      else
        run_as_user "$PYTHON" -m venv .venv
      fi

      # Check again
      if [[ -x "$INSTALL_DIR/.venv/bin/python3" ]]; then
        VENV_PYTHON="$INSTALL_DIR/.venv/bin/python3"
      elif [[ -x "$INSTALL_DIR/.venv/bin/python" ]]; then
        VENV_PYTHON="$INSTALL_DIR/.venv/bin/python"
      else
        print_msg "Failed to create a working virtual environment" "$RED"
        print_msg "Will try to use system Python as fallback" "$YELLOW"
        VENV_PYTHON=$(which python3 || which python)
      fi
    fi

    print_msg "Using Python at $VENV_PYTHON for service" "$GREEN"

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
    <string>$VENV_PYTHON</string>
    <string>$INSTALL_DIR/main.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>WorkingDirectory</key><string>$INSTALL_DIR</string>
  <key>StandardOutPath</key><string>$INSTALL_DIR/out.log</string>
  <key>StandardErrorPath</key><string>$INSTALL_DIR/error.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
  </dict>
</dict>
</plist>
PLIST

    # Ensure the plist file has the correct permissions
    run_as_user chmod 644 "$LAUNCHD_PLIST"

    # Unload existing service if it exists
    print_msg "Unloading existing service if present..." "$BLUE"
    run_as_user launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true

    # Verify the plist file
    print_msg "Verifying plist file..." "$BLUE"
    if ! plutil -lint "$LAUNCHD_PLIST" &>/dev/null; then
      print_msg "Plist file validation failed" "$RED"
      print_msg "Attempting to fix plist file..." "$YELLOW"
      plutil -convert xml1 "$LAUNCHD_PLIST" || true
    fi

    # Load the service
    print_msg "Loading service..." "$BLUE"
    if run_as_user launchctl load -w "$LAUNCHD_PLIST"; then
      print_msg "Service created and started successfully" "$GREEN"

      # Verify the service is running
      if run_as_user launchctl list | grep -q "com.mqtt-device-monitor"; then
        print_msg "Service is running" "$GREEN"
      else
        print_msg "Service loaded but may not be running" "$YELLOW"
        print_msg "Starting service manually..." "$BLUE"
        run_as_user launchctl start com.mqtt-device-monitor || true
      fi
    else
      print_msg "Failed to load service" "$RED"
      print_msg "You can try starting it manually with: launchctl load -w $LAUNCHD_PLIST" "$YELLOW"
      print_msg "Or run directly with: $VENV_PYTHON $INSTALL_DIR/main.py" "$YELLOW"
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

  # Run system update for Linux systems
  if [[ "$(uname -s)" == "Linux" ]]; then
    print_msg "Updating Linux system packages..." "$BLUE"
    if command_exists apt-get; then
      print_msg "Running apt update and upgrade..." "$BLUE"
      sudo apt update && sudo apt upgrade -y
      print_msg "System update completed" "$GREEN"
    else
      print_msg "apt-get not found, skipping system update" "$YELLOW"
    fi
  fi

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

  # Step 2.5: Configure Mosquitto MQTT broker
  print_msg "Step 2.5: Checking and configuring Mosquitto MQTT broker..." "$BLUE"
  if ! configure_mosquitto; then
    print_msg "Mosquitto configuration had issues" "$YELLOW"
    print_msg "Continuing anyway, but MQTT functionality might be limited" "$YELLOW"
  else
    print_msg "Mosquitto MQTT broker configured" "$GREEN"
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
  if command_exists mosquitto; then
    print_msg "MQTT broker is available on:" "$GREEN"
    print_msg "- MQTT: $ip:1883" "$GREEN"
    print_msg "- WebSockets: $ip:9001" "$GREEN"
  fi
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

  # Ask if user wants to remove Mosquitto
  if ask_yn "Would you like to uninstall Mosquitto MQTT broker as well?" false; then
    print_msg "Uninstalling Mosquitto MQTT broker..." "$BLUE"

    if [[ $OS == "linux" ]]; then
      # Linux uninstallation
      if command_exists apt-get; then
        print_msg "Removing Mosquitto using apt..." "$BLUE"
        require_root
        systemctl stop mosquitto || true
        systemctl disable mosquitto || true
        apt-get remove -y mosquitto mosquitto-clients || true
        apt-get autoremove -y || true
        # Remove configuration files
        if ask_yn "Remove Mosquitto configuration files as well?" false; then
          require_root
          rm -rf /etc/mosquitto || true
        fi
      elif command_exists pacman; then
        print_msg "Removing Mosquitto using pacman..." "$BLUE"
        require_root
        systemctl stop mosquitto || true
        systemctl disable mosquitto || true
        pacman -R --noconfirm mosquitto || true
        # Remove configuration files
        if ask_yn "Remove Mosquitto configuration files as well?" false; then
          require_root
          rm -rf /etc/mosquitto || true
        fi
      else
        print_msg "Could not determine package manager. Please uninstall Mosquitto manually." "$YELLOW"
      fi
    else
      # macOS uninstallation
      if command_exists brew; then
        print_msg "Removing Mosquitto using Homebrew..." "$BLUE"
        brew services stop mosquitto || true
        brew uninstall mosquitto || true
        # Remove configuration files
        if ask_yn "Remove Mosquitto configuration files as well?" false; then
          rm -rf "$(brew --prefix)/etc/mosquitto" || true
        fi
      else
        print_msg "Homebrew not found. Please uninstall Mosquitto manually." "$YELLOW"
      fi
    fi

    print_msg "Mosquitto uninstallation completed" "$GREEN"
  fi

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

  # Ask if user wants to configure Mosquitto
  if ask_yn "Would you like to check and configure Mosquitto MQTT broker?" false; then
    print_msg "Checking and configuring Mosquitto MQTT broker..." "$BLUE"
    if ! configure_mosquitto; then
      print_msg "Mosquitto configuration had issues" "$YELLOW"
      print_msg "Continuing with reconfiguration" "$YELLOW"
    else
      print_msg "Mosquitto MQTT broker configured" "$GREEN"
    fi
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

  # Determine local IP (best effort)
  local ip="localhost"
  if [[ $OS == macos ]]; then
    ip=$(ipconfig getifaddr en0 2>/dev/null || echo "localhost")
  elif command_exists hostname; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z $ip ]] && ip="localhost"
  fi

  print_msg "Reconfiguration complete – service restarted." "$GREEN"
  if command_exists mosquitto; then
    print_msg "MQTT broker is available on:" "$GREEN"
    print_msg "- MQTT: $ip:1883" "$GREEN"
    print_msg "- WebSockets: $ip:9001" "$GREEN"
  fi
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
