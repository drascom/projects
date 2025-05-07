#!/usr/bin/env bash
###############################################################################
# MQTT‑Device‑Monitor : non‑interactive installer / remover                   #
#                                                                             #
#   ▸ Debian / Ubuntu (systemd)                                               #
#   ▸ macOS (launchd)                                                         #
#                                                                             #
#   Installs client + web GUI with **fixed credentials**                     #
#       user : admin                                                          #
#       pass : admin                                                          #
#                                                                             #
#   curl -fsSL https://raw.githubusercontent.com/drascom/projects/main/mqtt-monitor/manage.sh | bash
#                                                                             #
#   1st run  → installs everything                                            #
#   2nd run  → removes everything                                             #
#                                                                             #
#   Flags:  --install | --uninstall | --help                                   #
###############################################################################
set -Eeuo pipefail

############################ Globals & helpers ################################
INSTALL_DIR="/opt/mqtt-device-monitor"
REPO_URL="https://github.com/drascom/projects.git"
SYSTEMD_UNIT="/etc/systemd/system/mqtt-device-monitor.service"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.mqtt-device-monitor.plist"
PYTHON="python3"
OS="" DISTRO=""
ACTUAL_USER=${SUDO_USER:-$(id -un)}

# fixed credentials -----------------------------------------------------------
MQTT_USER="admin"
MQTT_PASS="admin"

# colours --------------------------------------------------------------------
RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; NC="\033[0m"
msg() { printf "%b%s%b\n" "${2:-$GREEN}" "$1" "$NC" >&2; }
require_root() { ((EUID==0)) || { msg "❌  Must run as root" "$RED"; exit 1; }; }
cmd_exists()  { command -v "$1" &>/dev/null; }
run_as_user() { sudo -u "$ACTUAL_USER" "$@"; }

############################ Detect OS #######################################
detect_os() {
  case $(uname -s) in
    Linux*)  OS="linux" ;;
    Darwin*) OS="macos" ;;
    *) msg "Unsupported OS $(uname -s)" "$RED"; exit 1 ;;
  esac
  if [[ $OS == linux ]]; then source /etc/os-release; DISTRO=${ID:-unknown}; fi
  msg "Detected $OS${DISTRO:+/$DISTRO}" "$BLUE"
}

############################ Packages ########################################
install_deps() {
  msg "Installing packages …" "$BLUE"
  if [[ $OS == linux ]]; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git curl build-essential $PYTHON $PYTHON-venv
  else
    if ! cmd_exists brew; then
      msg "Installing Homebrew …" "$YELLOW"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv || /usr/local/bin/brew shellenv)"
    fi
    brew update
    brew install git $PYTHON || true
  fi
}

############################ Application #####################################
fetch_repo() {
  [[ -d $INSTALL_DIR ]] && { msg "Replacing previous install" "$YELLOW"; rm -rf "$INSTALL_DIR"; }
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  [[ -f $INSTALL_DIR/mqtt-monitor/main.py ]] || { msg "Repo layout unexpected" "$RED"; exit 1; }
}

setup_venv() {
  cd "$INSTALL_DIR/mqtt-monitor"
  $PYTHON -m venv .venv
  . .venv/bin/activate
  pip install --upgrade pip
  [[ -f requirements.txt ]] && pip install -r requirements.txt
  deactivate
}

create_env() {
  cd "$INSTALL_DIR/mqtt-monitor"
  local env=.env broker="localhost" port=9001 gui_port=9876 id="$(hostname)"
  cat >"$env" <<EOF
MQTT_BROKER=$broker
MQTT_PORT=$port
MQTT_USERNAME=$MQTT_USER
MQTT_PASSWORD=$MQTT_PASS
DEVICE_ID=$id
GUI_HOST=0.0.0.0
GUI_PORT=$gui_port
EOF
  chmod 600 "$env"

  # also create update.sh
  cat >"update.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"

read -p "MQTT_BROKER [localhost]: " broker
broker=${broker:-localhost}

read -p "MQTT_PORT [9001]: " port
port=${port:-9001}

read -p "MQTT_USERNAME [admin]: " username
username=${username:-admin}

read -p "MQTT_PASSWORD [admin]: " password
password=${password:-admin}

read -p "GUI_PORT [9876]: " gui_port
gui_port=${gui_port:-9876}

id=$(hostname)

cat >"$ENV_FILE" <<EOL
MQTT_BROKER=$broker
MQTT_PORT=$port
MQTT_USERNAME=$username
MQTT_PASSWORD=$password
DEVICE_ID=$id
GUI_HOST=0.0.0.0
GUI_PORT=$gui_port
EOL

echo "✅ .env updated successfully."
EOF
  chmod +x update.sh
}

create_service() {
  if [[ $OS == linux ]]; then
    cat >"$SYSTEMD_UNIT" <<EOF
[Unit]
Description=MQTT Device Monitor
After=network.target
[Service]
Type=simple
User=$ACTUAL_USER
WorkingDirectory=$INSTALL_DIR/mqtt-monitor
ExecStart=$INSTALL_DIR/mqtt-monitor/.venv/bin/python main.py
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now mqtt-device-monitor.service
  else
    cat >"$LAUNCHD_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.mqtt-device-monitor</string>
  <key>ProgramArguments</key><array>
    <string>$INSTALL_DIR/mqtt-monitor/.venv/bin/python</string>
    <string>$INSTALL_DIR/mqtt-monitor/main.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>WorkingDirectory</key><string>$INSTALL_DIR/mqtt-monitor</string>
</dict></plist>
EOF
    chown "$ACTUAL_USER" "$LAUNCHD_PLIST"
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
    launchctl load "$LAUNCHD_PLIST"
  fi
}

############################ Uninstall #######################################
remove_all() {
  msg "Removing installation …" "$BLUE"
  [[ -f $SYSTEMD_UNIT ]] && { systemctl disable --now mqtt-device-monitor.service || true; rm -f "$SYSTEMD_UNIT"; systemctl daemon-reload; }
  [[ -f $LAUNCHD_PLIST ]] && { launchctl unload "$LAUNCHD_PLIST" || true; rm -f "$LAUNCHD_PLIST"; }
  rm -rf "$INSTALL_DIR"
  msg "Uninstall complete" "$GREEN"
}

############################ CLI #############################################
OP=auto
case "${1:-}" in
  --install)   OP=install ;;
  --uninstall) OP=uninstall ;;
  -h|--help)   grep -m1 -A99 "^###############################################################################" "$0" | sed '1,2d;/^###############################################################################/q'; exit 0 ;;
esac

require_root
detect_os

if [[ $OP == auto ]]; then
  if [[ -d $INSTALL_DIR ]]; then
    OP="uninstall"
  else
    OP="install"
  fi
fi

if [[ $OP == uninstall ]]; then
  remove_all
  exit 0
fi

# ---------- install flow -----------------------------------------------------
install_deps
fetch_repo
setup_venv
create_env
run_as_user bash "$INSTALL_DIR/mqtt-monitor/update.sh"
create_service
msg "✅  Installation complete – GUI on http://$(hostname -I 2>/dev/null | awk '{print $1}'):${gui_port:-9876}  (admin/admin)" "$GREEN"
